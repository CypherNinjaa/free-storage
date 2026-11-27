package app.alextran.immich.keepsake

import android.media.MediaDataSource
import android.util.LruCache
import kotlinx.coroutines.runBlocking
import java.util.concurrent.ConcurrentHashMap

/**
 * An asset stored in Telegram, opened for reading. Encrypted files ([header] set) are read and decrypted one
 * IMTG segment at a time; plain files are read directly in [RemoteAssetReader.PLAIN_SEGMENT_BYTES] blocks.
 * [fileId] is the Telegram file of part 0; the other parts of a split asset are resolved when first read.
 */
class RemoteFile(val record: IndexRecord, val dek: ByteArray?, @Volatile var fileId: Int, val header: SegmentedCipher.Header?) {
  val size: Long get() = header?.plaintextSize ?: record.sizeBytes
  val segmentSize: Long get() = header?.segmentSize?.toLong() ?: RemoteAssetReader.PLAIN_SEGMENT_BYTES
  val layout: PartLayout? = record.layout
}

class RemoteAssetReader(
  private val client: TdClient,
  private val index: KeepsakeIndex,
  private val vault: VaultStore,
) {
  private val headers = ConcurrentHashMap<String, SegmentedCipher.Header>()

  /**
   * TDLib file ids are only valid inside one TDLib session: after an app restart the same number can name a
   * different file. Ids are therefore resolved from the asset's Telegram message once per run and kept here;
   * the id stored in the index is informational only.
   */
  private val sessionFileIds = ConcurrentHashMap<String, Int>()

  @Volatile
  private var chatsLoaded = false

  private val segments = object : LruCache<String, ByteArray>(SEGMENT_CACHE_BYTES) {
    override fun sizeOf(key: String, value: ByteArray) = value.size
  }

  suspend fun open(record: IndexRecord): RemoteFile {
    if (!record.isEncrypted) return RemoteFile(record, null, fileIdFor(record), null)
    val dek = VaultCrypto.open(VaultCrypto.subkey(vault.requireKey(), "dek"), record.wrappedDek, record.id.toByteArray())
    var fileId = fileIdFor(record)
    val header = headers[record.id] ?: run {
      val parsed = runCatching { readHeader(record, fileId) }.getOrElse {
        // The message may have been re-fetched with a new file id; resolve it again and retry once.
        fileId = fileIdFor(record, refresh = true)
        readHeader(record, fileId)
      }
      parsed.also { headers[record.id] = it }
    }
    return RemoteFile(record, dek, fileId, header)
  }

  /** Remembers the file id of an upload that just finished, so this session can read it without a lookup. */
  fun rememberSessionFileId(assetId: String, fileId: Int, part: Int = 0) {
    sessionFileIds[partKey(assetId, part)] = fileId
  }

  suspend fun segment(file: RemoteFile, segmentIndex: Long): ByteArray {
    val key = "${file.record.id}:$segmentIndex"
    segments.get(key)?.let { return it }
    val header = file.header
    val offset: Long
    val length: Int
    if (header != null) {
      offset = header.segmentOffset(segmentIndex)
      length = header.segmentEncryptedLength(segmentIndex)
    } else {
      offset = segmentIndex * PLAIN_SEGMENT_BYTES
      length = minOf(PLAIN_SEGMENT_BYTES, file.size - offset).toInt()
    }
    val (part, partOffset) = file.layout?.locate(offset) ?: (0 to offset)
    val bytes = try {
      client.downloadRange(partFileId(file, part), partOffset, length)
    } catch (error: TdException) {
      client.downloadRange(partFileId(file, part, refresh = true), partOffset, length)
    }
    val plaintext = if (header == null) bytes else SegmentedCipher.decryptSegment(checkNotNull(file.dek), header, segmentIndex, bytes)
    return plaintext.also { segments.put(key, it) }
  }

  /** The Telegram file holding [part] of [file] (part 0 for assets stored in one file). */
  private suspend fun partFileId(file: RemoteFile, part: Int, refresh: Boolean = false): Int {
    if (part == 0) {
      if (refresh) file.fileId = fileIdFor(file.record, refresh = true)
      return file.fileId
    }
    val key = partKey(file.record.id, part)
    if (!refresh) sessionFileIds[key]?.let { return it }
    val ref = index.parts(file.record.id).firstOrNull { it.index == part }
      ?: throw IllegalStateException("Part ${part + 1} of ${file.record.name} is missing from the index")
    return resolveFileId(ref.chatId, ref.messageId, file.record.name).also { sessionFileIds[key] = it }
  }

  suspend fun read(file: RemoteFile, position: Long, buffer: ByteArray, offset: Int, length: Int): Int {
    if (position >= file.size) return -1
    var copied = 0
    var cursor = position
    while (copied < length && cursor < file.size) {
      val segmentIndex = cursor / file.segmentSize
      val plaintext = segment(file, segmentIndex)
      val inSegment = (cursor - segmentIndex * file.segmentSize).toInt()
      val take = minOf(length - copied, plaintext.size - inSegment)
      System.arraycopy(plaintext, inSegment, buffer, offset + copied, take)
      copied += take
      cursor += take
    }
    return copied
  }

  fun forget(assetId: String) {
    headers.remove(assetId)
    sessionFileIds.keys.removeIf { it == assetId || it.startsWith("$assetId#") }
  }

  fun mediaDataSource(file: RemoteFile): MediaDataSource = object : MediaDataSource() {
    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int =
      runBlocking { read(file, position, buffer, offset, size) }

    override fun getSize(): Long = file.size

    override fun close() = Unit
  }

  private suspend fun readHeader(record: IndexRecord, fileId: Int): SegmentedCipher.Header {
    val header = SegmentedCipher.Header.parse(client.downloadRange(fileId, 0, SegmentedCipher.HEADER_SIZE))
    check(record.encryptedSize <= 0 || header.encryptedSize == record.encryptedSize) {
      "Telegram file for ${record.name} has ${header.encryptedSize} bytes, expected ${record.encryptedSize}"
    }
    return header
  }

  private suspend fun fileIdFor(record: IndexRecord, refresh: Boolean = false): Int {
    if (!refresh) sessionFileIds[record.id]?.let { return it }
    val fileId = resolveFileId(record.chatId, record.messageId, record.name)
    sessionFileIds[record.id] = fileId
    index.updateFileId(record.id, fileId)
    return fileId
  }

  private suspend fun resolveFileId(chatId: Long, messageId: Long, name: String): Int {
    if (!chatsLoaded) {
      client.loadChats()
      chatsLoaded = true
    }
    return client.documentFileId(chatId, messageId)
      ?: run {
        // Opening the chat makes TDLib fetch it if it was not in the loaded chat list yet.
        runCatching { client.chat(chatId) }
        client.documentFileId(chatId, messageId)
      }
      ?: throw IllegalStateException("The Telegram message for $name no longer exists")
  }

  private fun partKey(assetId: String, part: Int): String = if (part == 0) assetId else "$assetId#$part"

  companion object {
    private const val SEGMENT_CACHE_BYTES = 24 * 1024 * 1024

    /** Read size for files stored without encryption; matches the IMTG segment size. */
    const val PLAIN_SEGMENT_BYTES = 1024L * 1024
  }
}
