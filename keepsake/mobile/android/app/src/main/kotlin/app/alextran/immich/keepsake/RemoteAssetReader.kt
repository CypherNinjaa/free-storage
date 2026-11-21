package app.alextran.immich.keepsake

import android.media.MediaDataSource
import android.util.LruCache
import kotlinx.coroutines.runBlocking
import java.util.concurrent.ConcurrentHashMap

/**
 * An asset stored in Telegram, opened for reading. Encrypted files ([header] set) are read and decrypted one
 * IMTG segment at a time; plain files are read directly in [RemoteAssetReader.PLAIN_SEGMENT_BYTES] blocks.
 */
class RemoteFile(val record: IndexRecord, val dek: ByteArray?, @Volatile var fileId: Int, val header: SegmentedCipher.Header?) {
  val size: Long get() = header?.plaintextSize ?: record.sizeBytes
  val segmentSize: Long get() = header?.segmentSize?.toLong() ?: RemoteAssetReader.PLAIN_SEGMENT_BYTES
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
  fun rememberSessionFileId(assetId: String, fileId: Int) {
    sessionFileIds[assetId] = fileId
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
    val bytes = try {
      client.downloadRange(file.fileId, offset, length)
    } catch (error: TdException) {
      file.fileId = fileIdFor(file.record, refresh = true)
      client.downloadRange(file.fileId, offset, length)
    }
    val plaintext = if (header == null) bytes else SegmentedCipher.decryptSegment(checkNotNull(file.dek), header, segmentIndex, bytes)
    return plaintext.also { segments.put(key, it) }
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
    sessionFileIds.remove(assetId)
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
    if (!chatsLoaded) {
      client.loadChats()
      chatsLoaded = true
    }
    val fileId = client.documentFileId(record.chatId, record.messageId)
      ?: run {
        // Opening the chat makes TDLib fetch it if it was not in the loaded chat list yet.
        runCatching { client.chat(record.chatId) }
        client.documentFileId(record.chatId, record.messageId)
      }
      ?: throw IllegalStateException("The Telegram message for ${record.name} no longer exists")
    sessionFileIds[record.id] = fileId
    index.updateFileId(record.id, fileId)
    return fileId
  }

  companion object {
    private const val SEGMENT_CACHE_BYTES = 24 * 1024 * 1024

    /** Read size for files stored without encryption; matches the IMTG segment size. */
    const val PLAIN_SEGMENT_BYTES = 1024L * 1024
  }
}
