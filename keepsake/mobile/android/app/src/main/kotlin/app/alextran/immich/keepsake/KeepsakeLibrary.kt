package app.alextran.immich.keepsake

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.util.Log
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.security.DigestInputStream
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

/** The phone lacks the free space needed to prepare a file for upload. */
class NotEnoughSpaceException(message: String) : IllegalStateException(message)

/** The original changed while it was being backed up; the next run backs up the new version. */
class ChangedDuringBackupException(message: String) : IllegalStateException(message)

/** Telegram asked for a pause longer than is worth waiting inside one request; uploads continue after it. */
class FloodWaitException(val seconds: Long) : IllegalStateException(
  "Telegram asked Ambry to pause uploads for ${formatWait(seconds)}. Backup continues after that."
)

private fun formatWait(seconds: Long): String = when {
  seconds < 120 -> "$seconds seconds"
  seconds < 2 * 3600 -> "${(seconds + 59) / 60} minutes"
  else -> "${(seconds + 3599) / 3600} hours"
}

/** The phone that currently owns the vault: the newest sealed device claim in the System channel. */
@Serializable
data class DeviceClaim(val deviceId: String, val deviceName: String, val claimedAtMs: Long)

/** Another phone claimed the vault after this one; writing now could overwrite that phone's index and albums. */
class VaultInUseException(val holder: DeviceClaim) : IllegalStateException(
  "Ambry is now active on ${holder.deviceName}. This phone stopped writing to the vault so it does not overwrite " +
    "that phone's changes."
)

data class IndexBackupState(val lastSnapshotAtMs: Long?, val pendingChanges: Long, val assetCount: Long, val albumCount: Long)

data class BackupHints(
  val localId: String,
  val checksum: String?,
  val createdAtMs: Long?,
  val modifiedAtMs: Long?,
  val isFavorite: Boolean,
)

data class AssetUpdate(
  val ids: List<String>,
  val isFavorite: Boolean? = null,
  val visibility: Int? = null,
  val createdAtMs: Long? = null,
  val latitude: Double? = null,
  val longitude: Double? = null,
)

data class VaultDiscovery(
  val descriptorJson: String,
  val vaultName: String,
  val libraryChatId: Long,
  val systemChatId: Long,
)

@Serializable
data class SnapshotManifest(
  val snapshotId: String,
  val createdAtMs: Long,
  val assetCount: Long,
  val libraryChatId: Long,
  val systemChatId: Long,
  val dek: String,
  /** The index database was gzipped before it was encrypted; snapshots made before this field existed were not. */
  val compressed: Boolean = false,
)

class KeepsakeLibrary(
  private val context: Context,
  private val client: TdClient,
  private val vault: VaultStore,
  private val channels: TelegramVault,
  val index: KeepsakeIndex,
  private val thumbnails: ThumbnailStore,
  private val reader: RemoteAssetReader,
  private val media: LocalMediaReader,
) {
  private val rendering = Semaphore(2)
  private val snapshotLock = Semaphore(1)
  /** One split upload at a time: each stages a part (256 MiB encrypted, up to 1.9 GiB plain) in the cache. */
  private val largeUploads = Mutex()
  private val json = Json { ignoreUnknownKeys = true }

  /** Until when Telegram asked this phone to stop sending (flood wait), in wall-clock milliseconds. */
  @Volatile
  private var floodUntilMs = 0L

  /** Whether new uploads are encrypted (the default) or stored as the original file, viewable in Telegram. */
  fun encryptUploads(): Boolean = index.meta(META_ENCRYPT_UPLOADS) != "0"

  fun setEncryptUploads(enabled: Boolean) = index.putMeta(META_ENCRYPT_UPLOADS, if (enabled) "1" else "0")

  suspend fun backup(hints: BackupHints): IndexRecord {
    hints.checksum?.let(index::findByChecksum)?.let { return it }
    ensureActiveWriter()
    val key = vault.requireKey()
    val target = channels.channels() ?: throw IllegalStateException("The vault channels are not set up yet")
    val info = media.info(hints.localId)
    val size = media.originalSize(info)
    val encrypt = encryptUploads()
    if (size > if (encrypt) SPLIT_ENCRYPTED_ABOVE_BYTES else MAX_OBJECT_BYTES) {
      return largeUploads.withLock { backupInParts(hints, info, size, key, target, encrypt) }
    }
    requireFreeSpace(size + STAGING_HEADROOM_BYTES, info.name)
    val details = media.details(info)
    val assetId = UUID.randomUUID().toString()
    val staging = File(context.cacheDir, "keepsake-upload-$assetId").apply { mkdirs() }
    try {
      val staged = if (encrypt) stageEncrypted(info, size, File(staging, "$assetId.imtg")) else stagePlain(info, staging)
      val checksum = Base64.getEncoder().encodeToString(hexToBytes(staged.sha1Hex))
      index.findByChecksum(checksum)?.let { return it }

      val createdAtMs = info.dateTakenMs ?: hints.createdAtMs ?: info.modifiedMs ?: System.currentTimeMillis()
      val caption = VaultCaption.encode(
        key,
        RecoveryRecord(
          assetId = assetId,
          sha1 = staged.sha1Hex,
          takenAtEpochSec = createdAtMs / 1000,
          sizeBytes = staged.plainSize,
          mimeType = info.mimeType,
          fileName = info.name,
          dek = staged.dek?.let { Base64.getEncoder().encodeToString(it) }.orEmpty(),
          format = staged.format,
        ),
      )
      // Plain files are visible in Telegram, so they get a thumbnail there too; render the previews first.
      val earlyPreviews = if (staged.format == KeepsakeIndex.FORMAT_PLAIN) media.renderPreviews(info, details) else null
      val telegramThumbnail = earlyPreviews?.let { LocalMediaReader.telegramThumbnail(it.preview) }?.let { (bytes, width, height) ->
        val file = File(staging, "thumbnail.jpg").apply { writeBytes(bytes) }
        DocumentThumbnail(file.absolutePath, width, height)
      }
      val document = withFloodRetry {
        client.sendDocument(target.libraryChatId, staged.file.absolutePath, caption, thumbnail = telegramThumbnail)
      }
      check(document.fileSize == staged.storedSize) {
        "Telegram stored ${document.fileSize} bytes for ${info.name}, expected ${staged.storedSize}"
      }
      checkNotNull(client.getMessages(target.libraryChatId, listOf(document.messageId)).singleOrNull()) {
        "Telegram did not confirm the upload of ${info.name}"
      }

      reader.rememberSessionFileId(assetId, document.fileId)
      val previews = earlyPreviews ?: media.renderPreviews(info, details)
      if (previews != null) {
        thumbnails.put(assetId, ThumbnailStore.Kind.THUMBNAIL, previews.thumbnail)
        thumbnails.put(assetId, ThumbnailStore.Kind.PREVIEW, previews.preview)
      }
      index.upsert(
        assetRecord(
          assetId = assetId,
          checksum = checksum,
          info = info,
          details = details,
          hints = hints,
          createdAtMs = createdAtMs,
          sizeBytes = staged.plainSize,
          stored = UploadedPart(0, target.libraryChatId, document.messageId, document.fileId, document.fileUniqueId, document.fileSize),
          wrappedDek = staged.dek?.let { wrapDek(key, assetId, it) } ?: ByteArray(0),
          hasThumbnail = previews != null,
          format = staged.format,
        )
      )
      return checkNotNull(index.find(assetId))
    } finally {
      staging.deleteRecursively()
    }
  }

  /** The index row of a fresh upload; [stored] is its Telegram message (part 0 of a split asset). */
  private fun assetRecord(
    assetId: String,
    checksum: String,
    info: LocalMediaInfo,
    details: MediaDetails,
    hints: BackupHints,
    createdAtMs: Long,
    sizeBytes: Long,
    stored: UploadedPart,
    wrappedDek: ByteArray,
    hasThumbnail: Boolean,
    format: Int,
    layout: PartLayout? = null,
    encryptedSize: Long = stored.storedSize,
  ) = IndexRecord(
    id = assetId,
    checksum = checksum,
    localId = info.localId,
    name = info.name,
    mimeType = info.mimeType,
    type = if (info.isVideo) KeepsakeIndex.TYPE_VIDEO else KeepsakeIndex.TYPE_IMAGE,
    createdAtMs = createdAtMs,
    modifiedAtMs = hints.modifiedAtMs ?: info.modifiedMs ?: createdAtMs,
    width = details.width ?: info.width,
    height = details.height ?: info.height,
    durationMs = details.durationMs ?: info.durationMs,
    sizeBytes = sizeBytes,
    latitude = details.latitude,
    longitude = details.longitude,
    make = details.make,
    model = details.model,
    orientation = details.orientation,
    isFavorite = hints.isFavorite,
    visibility = 0,
    deletedAtMs = null,
    uploadedAtMs = System.currentTimeMillis(),
    chatId = stored.chatId,
    messageId = stored.messageId,
    fileId = stored.fileId,
    fileUniqueId = stored.fileUniqueId,
    encryptedSize = encryptedSize,
    wrappedDek = wrappedDek,
    hasThumbnail = hasThumbnail,
    format = format,
    partCount = layout?.partCount ?: 1,
    partBytes = layout?.partPlainBytes ?: 0,
  )

  /**
   * Backs up a large original as [PartLayout] parts, one message each (see [SPLIT_ENCRYPTED_ABOVE_BYTES] and
   * [MAX_OBJECT_BYTES]). Progress is saved after every part ([PendingUpload]), so an interrupted upload continues
   * with the next part instead of restarting.
   */
  private suspend fun backupInParts(
    hints: BackupHints,
    info: LocalMediaInfo,
    size: Long,
    key: ByteArray,
    target: ChannelState,
    encrypt: Boolean,
  ): IndexRecord {
    val format = if (encrypt) KeepsakeIndex.FORMAT_ENCRYPTED else KeepsakeIndex.FORMAT_PLAIN
    val layout = PartLayout(size, if (encrypt) ENCRYPTED_PART_BYTES else PLAIN_PART_BYTES, encrypted = encrypt)
    requireFreeSpace(layout.storedSize(0) + STAGING_HEADROOM_BYTES, info.name)
    // One read of the whole original gives the asset checksum and a checksum per part. Every part is compared with
    // its checksum before it is sent, so an original that changes meanwhile is never stored half old, half new.
    val (sha1Hex, partSha1) = media.openOriginal(info).use { hashParts(it, layout, info.name) }
    val checksum = Base64.getEncoder().encodeToString(hexToBytes(sha1Hex))
    index.findByChecksum(checksum)?.let { return it }

    var state = resumeOrStartPartUpload(checksum, layout, format, partSha1, key)
    val assetId = state.assetId
    Log.i(TAG, "Split upload $assetId: ${layout.partCount} parts, ${state.uploaded.size} already in Telegram")
    val wrappedDek = state.wrappedDek.takeIf { it.isNotEmpty() }?.let { Base64.getDecoder().decode(it) }
    val dek = wrappedDek?.let { unwrapDek(key, assetId, it) }
    val header = state.baseNonce.takeIf { it.isNotEmpty() }?.let {
      SegmentedCipher.Header(SegmentedCipher.SEGMENT_SIZE, size, Base64.getDecoder().decode(it))
    }
    val createdAtMs = info.dateTakenMs ?: hints.createdAtMs ?: info.modifiedMs ?: System.currentTimeMillis()
    val details = media.details(info)
    val previews = media.renderPreviews(info, details)
    val staging = File(context.cacheDir, "keepsake-upload-$assetId").apply { mkdirs() }
    try {
      // Plain parts are visible in Telegram, so the first one gets a thumbnail there.
      val telegramThumbnail = if (layout.encrypted) null else previews?.let { LocalMediaReader.telegramThumbnail(it.preview) }
        ?.let { (bytes, width, height) ->
          DocumentThumbnail(File(staging, "thumbnail.jpg").apply { writeBytes(bytes) }.absolutePath, width, height)
        }
      for (part in 0 until layout.partCount) {
        if (state.uploaded.any { it.index == part }) continue
        val partFile = File(staging, partFileName(info.name, assetId, part, layout))
        try {
          val stagedSha1 = media.openOriginal(info).use { stagePart(it, layout, part, dek, header, partFile, info.name) }
          if (stagedSha1 != state.partSha1[part]) {
            discardPendingUpload(state)
            throw ChangedDuringBackupException("${info.name} changed while it was being backed up; it will be backed up again")
          }
          val caption = VaultCaption.encode(
            key,
            RecoveryRecord(
              assetId = assetId,
              sha1 = sha1Hex,
              takenAtEpochSec = createdAtMs / 1000,
              sizeBytes = size,
              mimeType = info.mimeType,
              fileName = info.name,
              dek = dek?.let { Base64.getEncoder().encodeToString(it) }.orEmpty(),
              format = format,
              partIndex = part,
              partCount = layout.partCount,
              partBytes = layout.partPlainBytes,
            ),
          )
          val document = withFloodRetry {
            client.sendDocument(
              target.libraryChatId,
              partFile.absolutePath,
              caption,
              timeoutMs = uploadTimeoutMs(layout.storedSize(part)),
              thumbnail = telegramThumbnail?.takeIf { part == 0 },
            )
          }
          check(document.fileSize == layout.storedSize(part)) {
            "Telegram stored ${document.fileSize} bytes for part ${part + 1} of ${info.name}, expected ${layout.storedSize(part)}"
          }
          reader.rememberSessionFileId(assetId, document.fileId, part)
          Log.i(TAG, "Split upload $assetId: part ${part + 1}/${layout.partCount} stored (${document.fileSize} bytes)")
          state = state.copy(
            uploaded = state.uploaded +
              UploadedPart(part, document.chatId, document.messageId, document.fileId, document.fileUniqueId, document.fileSize),
            updatedAtMs = System.currentTimeMillis(),
          )
          savePendingUpload(state)
        } finally {
          partFile.delete()
        }
      }

      val parts = state.uploaded.sortedBy { it.index }
      check(parts.map { it.index } == (0 until layout.partCount).toList()) { "Some parts of ${info.name} are missing" }
      for ((chatId, group) in parts.groupBy { it.chatId }) {
        val found = withFloodRetry { client.getMessages(chatId, group.map { it.messageId }) }
        check(found.size == group.size && found.none { it == null }) { "Telegram did not confirm every part of ${info.name}" }
      }
      if (previews != null) {
        thumbnails.put(assetId, ThumbnailStore.Kind.THUMBNAIL, previews.thumbnail)
        thumbnails.put(assetId, ThumbnailStore.Kind.PREVIEW, previews.preview)
      }
      index.upsert(
        assetRecord(
          assetId = assetId,
          checksum = checksum,
          info = info,
          details = details,
          hints = hints,
          createdAtMs = createdAtMs,
          sizeBytes = size,
          stored = parts.first(),
          wrappedDek = wrappedDek ?: ByteArray(0),
          hasThumbnail = previews != null,
          format = format,
          layout = layout,
          encryptedSize = parts.sumOf { it.storedSize },
        ),
        parts.map { PartRef(it.index, it.chatId, it.messageId, it.fileId, it.storedSize) },
      )
      index.deleteMeta(pendingKey(checksum))
      Log.i(TAG, "Split upload $assetId: all ${layout.partCount} parts confirmed")
      return checkNotNull(index.find(assetId))
    } finally {
      staging.deleteRecursively()
    }
  }

  /** SHA-1 (hex) of the whole original and of each part's bytes, from one read. */
  private fun hashParts(input: InputStream, layout: PartLayout, name: String): Pair<String, List<String>> {
    val whole = MessageDigest.getInstance("SHA-1")
    val buffer = ByteArray(COPY_BUFFER_BYTES)
    val parts = (0 until layout.partCount).map { part ->
      val digest = MessageDigest.getInstance("SHA-1")
      var remaining = layout.plainEnd(part) - layout.plainStart(part)
      while (remaining > 0) {
        val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
        if (read < 0) throw ChangedDuringBackupException("$name became shorter while it was being backed up")
        digest.update(buffer, 0, read)
        whole.update(buffer, 0, read)
        remaining -= read
      }
      digest.digest().toHex()
    }
    if (input.read() != -1) throw ChangedDuringBackupException("$name became longer while it was being backed up")
    return whole.digest().toHex() to parts
  }

  /** Writes part [part] to [target] exactly as it is stored in Telegram; returns the SHA-1 (hex) of its original bytes. */
  private fun stagePart(
    input: InputStream,
    layout: PartLayout,
    part: Int,
    dek: ByteArray?,
    header: SegmentedCipher.Header?,
    target: File,
    name: String,
  ): String {
    skipFully(input, layout.plainStart(part), name)
    val digest = MessageDigest.getInstance("SHA-1")
    target.outputStream().buffered(COPY_BUFFER_BYTES).use { output ->
      if (layout.encrypted) {
        val cipherHeader = checkNotNull(header) { "Missing encryption header" }
        if (part == 0) output.write(cipherHeader.bytes)
        SegmentedCipher.encryptSegments(
          input, checkNotNull(dek) { "Missing file key" }, cipherHeader, layout.firstSegment(part), layout.segmentCount(part), output, digest,
        )
      } else {
        copyExactly(input, output, layout.plainEnd(part) - layout.plainStart(part), digest, name)
      }
    }
    check(target.length() == layout.storedSize(part)) {
      "Part ${part + 1} of $name has ${target.length()} bytes, expected ${layout.storedSize(part)}"
    }
    return digest.digest().toHex()
  }

  private fun skipFully(input: InputStream, bytes: Long, name: String) {
    var remaining = bytes
    var scratch: ByteArray? = null
    while (remaining > 0) {
      val skipped = input.skip(remaining)
      if (skipped > 0) {
        remaining -= skipped
        continue
      }
      // skip() may refuse to move; reading always does.
      val buffer = scratch ?: ByteArray(COPY_BUFFER_BYTES).also { scratch = it }
      val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
      if (read < 0) throw ChangedDuringBackupException("$name became shorter while it was being backed up")
      remaining -= read
    }
  }

  private fun copyExactly(input: InputStream, output: OutputStream, length: Long, digest: MessageDigest, name: String) {
    val buffer = ByteArray(COPY_BUFFER_BYTES)
    var remaining = length
    while (remaining > 0) {
      val read = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
      if (read < 0) throw ChangedDuringBackupException("$name became shorter while it was being backed up")
      digest.update(buffer, 0, read)
      output.write(buffer, 0, read)
      remaining -= read
    }
  }

  /** Encrypted parts are named after the asset id; plain parts after the original, numbered like split archives. */
  private fun partFileName(name: String, assetId: String, part: Int, layout: PartLayout): String =
    if (layout.encrypted) "$assetId.part${part + 1}.imtg" else "${safeFileName(name)}.${"%03d".format(part + 1)}"

  /** Continues the unfinished split upload of the same original, or starts a new one. */
  private suspend fun resumeOrStartPartUpload(
    checksum: String,
    layout: PartLayout,
    format: Int,
    partSha1: List<String>,
    key: ByteArray,
  ): PendingUpload {
    loadPendingUpload(checksum)?.let { pending ->
      val sameUpload = pending.plainSize == layout.plainSize && pending.partBytes == layout.partPlainBytes &&
        pending.format == format && pending.partSha1 == partSha1
      if (sameUpload) {
        // Keep the parts Telegram still has; any that were deleted are sent again.
        val alive = pending.uploaded.groupBy { it.chatId }.flatMap { (chatId, group) ->
          val found = withFloodRetry { client.getMessages(chatId, group.map { it.messageId }) }
          group.filterIndexed { position, _ -> found.getOrNull(position) != null }
        }
        return pending.copy(uploaded = alive, updatedAtMs = System.currentTimeMillis()).also(::savePendingUpload)
      }
      discardPendingUpload(pending)
    }
    val assetId = UUID.randomUUID().toString()
    val dek = if (layout.encrypted) VaultCrypto.randomBytes(VaultCrypto.KEY_BYTES) else null
    val encoder = Base64.getEncoder()
    return PendingUpload(
      assetId = assetId,
      checksum = checksum,
      plainSize = layout.plainSize,
      partBytes = layout.partPlainBytes,
      format = format,
      wrappedDek = dek?.let { encoder.encodeToString(wrapDek(key, assetId, it)) }.orEmpty(),
      baseNonce = if (layout.encrypted) encoder.encodeToString(SegmentedCipher.newHeader(layout.plainSize).baseNonce) else "",
      partSha1 = partSha1,
      uploaded = emptyList(),
      updatedAtMs = System.currentTimeMillis(),
    ).also(::savePendingUpload)
  }

  private fun pendingKey(checksum: String) = "$META_PENDING_UPLOAD_PREFIX$checksum"

  private fun loadPendingUpload(checksum: String): PendingUpload? =
    index.meta(pendingKey(checksum))?.let { runCatching { json.decodeFromString<PendingUpload>(it) }.getOrNull() }

  private fun savePendingUpload(state: PendingUpload) = index.putMeta(pendingKey(state.checksum), json.encodeToString(state))

  /** Deletes the parts an unfinished split upload left in Telegram, and forgets the upload. */
  private suspend fun discardPendingUpload(state: PendingUpload) {
    for ((chatId, group) in state.uploaded.groupBy { it.chatId }) {
      runCatching { withFloodRetry { client.deleteMessages(chatId, group.map { it.messageId }) } }
    }
    index.deleteMeta(pendingKey(state.checksum))
  }

  /** Split uploads untouched for [PENDING_UPLOAD_TTL_MS] were abandoned (for example, the video was deleted). */
  private suspend fun purgeAbandonedUploads() {
    val entries = index.metaWithPrefix(META_PENDING_UPLOAD_PREFIX)
    if (entries.isEmpty() || !largeUploads.tryLock()) return
    try {
      val cutoff = System.currentTimeMillis() - PENDING_UPLOAD_TTL_MS
      for ((metaKey, value) in entries) {
        val state = runCatching { json.decodeFromString<PendingUpload>(value) }.getOrNull()
        when {
          state == null -> index.deleteMeta(metaKey)
          state.updatedAtMs < cutoff -> {
            ensureActiveWriter()
            discardPendingUpload(state)
          }
        }
      }
    } finally {
      largeUploads.unlock()
    }
  }

  private fun requireFreeSpace(bytes: Long, name: String) {
    val free = context.cacheDir.usableSpace
    if (free < bytes) {
      throw NotEnoughSpaceException(
        "Not enough free space to back up $name: it needs ${bytes / MIB} MB free on the phone, ${free / MIB} MB are free"
      )
    }
  }

  /** At least an hour, more for big files: a part of about 1.9 GiB at 200 kB/s takes over two and a half hours. */
  private fun uploadTimeoutMs(bytes: Long): Long = maxOf(3_600_000L, bytes / MIN_UPLOAD_BYTES_PER_MS)

  /** A file ready to send to Telegram, with the facts the index and recovery caption need. */
  private class StagedUpload(
    val file: File,
    val sha1Hex: String,
    val plainSize: Long,
    val storedSize: Long,
    val dek: ByteArray?,
    val format: Int,
  )

  private fun stageEncrypted(info: LocalMediaInfo, size: Long, target: File): StagedUpload {
    val encryption = media.openOriginal(info).use { SegmentedCipher.encrypt(it, size, target) }
    return StagedUpload(
      file = target,
      sha1Hex = encryption.plaintextSha1,
      plainSize = encryption.header.plaintextSize,
      storedSize = encryption.header.encryptedSize,
      dek = encryption.dek,
      format = KeepsakeIndex.FORMAT_ENCRYPTED,
    )
  }

  /** Copies the original under its own name, so Telegram apps show and open it like any other file. */
  private fun stagePlain(info: LocalMediaInfo, directory: File): StagedUpload {
    val target = File(directory, safeFileName(info.name))
    val digest = MessageDigest.getInstance("SHA-1")
    media.openOriginal(info).use { input ->
      DigestInputStream(input, digest).use { hashed -> target.outputStream().use { hashed.copyTo(it, COPY_BUFFER_BYTES) } }
    }
    val sha1Hex = digest.digest().joinToString("") { "%02x".format(it) }
    return StagedUpload(target, sha1Hex, target.length(), target.length(), dek = null, format = KeepsakeIndex.FORMAT_PLAIN)
  }

  private fun safeFileName(name: String): String =
    name.replace(UNSAFE_FILE_NAME_CHARS, "_").trim().ifEmpty { "file" }.take(MAX_FILE_NAME_CHARS)

  fun trash(ids: List<String>): Int = index.update(ids, ContentValues().apply { put("deleted_at", System.currentTimeMillis()) })

  fun restore(ids: List<String>): Int = index.update(ids, ContentValues().apply { putNull("deleted_at") })

  fun restoreAllTrash(): Int = restore(index.trashedIds())

  suspend fun deletePermanently(ids: List<String>): Int {
    ensureActiveWriter()
    val records = index.findAll(ids)
    // A split asset is every one of its parts; others are their single message.
    val messages = records.flatMap { record ->
      index.parts(record.id).map { it.chatId to it.messageId }.ifEmpty { listOf(record.chatId to record.messageId) }
    }
    messages.groupBy({ it.first }, { it.second }).forEach { (chatId, messageIds) ->
      messageIds.chunked(100).forEach { chunk -> withFloodRetry { client.deleteMessages(chatId, chunk) } }
    }
    if (records.isNotEmpty()) Log.i(TAG, "Deleted ${messages.size} Telegram messages for ${records.size} assets")
    records.forEach {
      thumbnails.delete(it.id)
      reader.forget(it.id)
    }
    return index.delete(records.map { it.id })
  }

  suspend fun emptyTrash(): Int = deletePermanently(index.trashedIds())

  /** Like the Immich server, permanently deletes assets that have been in the trash for [TRASH_RETENTION_MS]. */
  suspend fun purgeExpiredTrash(): Int {
    val expired = index.trashedBefore(System.currentTimeMillis() - TRASH_RETENTION_MS)
    return if (expired.isEmpty()) 0 else deletePermanently(expired)
  }

  fun update(update: AssetUpdate): Int {
    val values = ContentValues()
    update.isFavorite?.let { values.put("is_favorite", if (it) 1 else 0) }
    update.visibility?.let { values.put("visibility", it) }
    update.createdAtMs?.let { values.put("created_at", it) }
    update.latitude?.let { values.put("latitude", it) }
    update.longitude?.let { values.put("longitude", it) }
    return if (values.size() == 0) 0 else index.update(update.ids, values)
  }

  fun updateDescription(id: String, description: String): Int =
    index.update(listOf(id), ContentValues().apply { put("description", description.ifBlank { null }) })

  fun updateRating(id: String, rating: Int?): Int =
    index.update(listOf(id), ContentValues().apply { if (rating == null) putNull("rating") else put("rating", rating) })

  suspend fun image(id: String, kind: ThumbnailStore.Kind): ByteArray? {
    thumbnails.get(id, kind)?.let { return it }
    val record = index.find(id) ?: return null
    requireTelegram()
    return rendering.withPermit {
      thumbnails.get(id, kind) ?: render(record)?.let { previews ->
        thumbnails.put(id, ThumbnailStore.Kind.THUMBNAIL, previews.thumbnail)
        thumbnails.put(id, ThumbnailStore.Kind.PREVIEW, previews.preview)
        index.markThumbnail(id)
        if (kind == ThumbnailStore.Kind.THUMBNAIL) previews.thumbnail else previews.preview
      }
    }
  }

  suspend fun openRemote(record: IndexRecord): RemoteFile {
    requireTelegram()
    return reader.open(record)
  }

  /** Remote reads can arrive (from the media server) before anything else has started the TDLib client. */
  private suspend fun requireTelegram() {
    client.start()
    check(client.awaitSettled().step == TdAuthStep.READY) { "Telegram is not connected" }
  }

  suspend fun copyPlaintext(file: RemoteFile, output: OutputStream, start: Long, endInclusive: Long) {
    if (file.size == 0L || endInclusive < start) return
    val segmentSize = file.segmentSize
    var position = start
    while (position <= endInclusive) {
      val segmentIndex = position / segmentSize
      val plaintext = reader.segment(file, segmentIndex)
      val inSegment = (position - segmentIndex * segmentSize).toInt()
      val take = minOf(plaintext.size - inSegment, (endInclusive - position + 1).toInt())
      output.write(plaintext, inSegment, take)
      position += take
    }
  }

  suspend fun publishVault(vaultName: String) {
    val target = channels.channels() ?: return
    val descriptor = vault.descriptorJson() ?: return
    val encoder = Base64.getUrlEncoder().withoutPadding()
    val text = listOf(
      VAULT_PREFIX,
      encoder.encodeToString(descriptor.toByteArray()),
      target.libraryChatId.toString(),
      target.systemChatId.toString(),
      encoder.encodeToString(vaultName.toByteArray()),
    ).joinToString(" ")
    val previous = systemMessages(target.systemChatId)
      .filter { messageText(it).startsWith("$VAULT_PREFIX ") }
      .map { it.getLong("id") }
    val messageId = withFloodRetry { client.sendText(target.systemChatId, text) }
    runCatching { client.pinMessage(target.systemChatId, messageId) }
    previous.filter { it != messageId }.takeIf { it.isNotEmpty() }?.let { client.deleteMessages(target.systemChatId, it) }
    index.putMeta(META_VAULT_PUBLISHED, System.currentTimeMillis().toString())
  }

  /** Vaults created before the discovery record existed get it published once, so a new phone can find them. */
  private suspend fun ensureVaultPublished() {
    if (index.meta(META_VAULT_PUBLISHED) != null) return
    val target = channels.channels() ?: return
    val title = runCatching { client.chat(target.systemChatId).optString("title") }.getOrNull().orEmpty()
    publishVault(title.substringAfter("· ", "").ifBlank { DEFAULT_VAULT_NAME })
  }

  suspend fun discoverVault(): VaultDiscovery? {
    client.loadChats()
    val candidates = SYSTEM_TITLE_PREFIXES.flatMap { client.searchChatIds(it) }.distinct()
    for (chatId in candidates) {
      val chat = runCatching { client.chat(chatId) }.getOrNull() ?: continue
      val title = chat.optString("title")
      if (SYSTEM_TITLE_PREFIXES.none { title.startsWith(it) }) continue
      val text = systemMessages(chatId).map { messageText(it) }.firstOrNull { it.startsWith("$VAULT_PREFIX ") } ?: continue
      val parts = text.split(' ')
      if (parts.size < 5) continue
      val decoder = Base64.getUrlDecoder()
      return VaultDiscovery(
        descriptorJson = String(decoder.decode(parts[1])),
        libraryChatId = parts[2].toLong(),
        systemChatId = parts[3].toLong(),
        vaultName = String(decoder.decode(parts[4])),
      )
    }
    return null
  }

  fun adopt(discovery: VaultDiscovery) {
    vault.importDescriptor(discovery.descriptorJson)
    channels.adopt(ChannelState(discovery.libraryChatId, discovery.systemChatId))
  }

  /**
   * Snapshots the index when forced, or when it changed and either [SNAPSHOT_INTERVAL_MS] passed or
   * [SNAPSHOT_CHANGE_THRESHOLD] changes piled up since the last snapshot. Returns -1 when nothing was due.
   */
  suspend fun snapshotIfDue(force: Boolean): Long = snapshotLock.withPermit {
    runCatching { ensureVaultPublished() }
    runCatching { purgeExpiredTrash() }
    runCatching { purgeAbandonedUploads() }
    val seq = index.currentSeq()
    val lastSeq = index.meta(META_SNAPSHOT_SEQ)?.toLongOrNull() ?: 0L
    val lastAt = index.meta(META_SNAPSHOT_AT)?.toLongOrNull() ?: 0L
    val now = System.currentTimeMillis()
    // Albums exist only in the index (assets can also be rebuilt from their captions), so album edits are
    // saved soon after they happen instead of waiting for the regular interval.
    val albumsDirty = seq != lastSeq && index.albumsChangedSince(lastSeq) && now - lastAt >= ALBUM_SNAPSHOT_SPACING_MS
    // A snapshot of a big library is tens of MB, so the change count that triggers one grows with the library
    // (assets can always be rebuilt from their captions; the interval still bounds what a lost phone can lose).
    val changeThreshold = maxOf(SNAPSHOT_CHANGE_THRESHOLD, index.count() / SNAPSHOT_CHANGE_DIVISOR)
    val due = force || albumsDirty ||
      (seq != lastSeq && (now - lastAt >= SNAPSHOT_INTERVAL_MS || seq - lastSeq >= changeThreshold))
    if (!due) return@withPermit -1L
    val count = snapshotIndex()
    index.putMeta(META_SNAPSHOT_SEQ, seq.toString())
    index.putMeta(META_SNAPSHOT_AT, now.toString())
    count
  }

  /** Uploads an encrypted copy of the index to the System channel and keeps the newest [SNAPSHOTS_TO_KEEP]. */
  suspend fun snapshotIndex(): Long {
    // A snapshot replaces what a new phone restores, so always confirm this phone still owns the vault.
    ensureActiveWriter(fresh = true)
    val key = vault.requireKey()
    val target = channels.channels() ?: throw IllegalStateException("The vault channels are not set up yet")
    val plain = File(context.cacheDir, "keepsake-index-${UUID.randomUUID()}.db")
    val packed = File(context.cacheDir, "keepsake-index-${UUID.randomUUID()}.db.gz")
    val encrypted = File(context.cacheDir, "keepsake-index-${UUID.randomUUID()}.imtg")
    try {
      index.exportTo(plain)
      // SQLite pages compress several times over; a 100k-asset index goes from tens of MB to a few.
      GZIPOutputStream(packed.outputStream().buffered(COPY_BUFFER_BYTES)).use { gzip ->
        plain.inputStream().use { it.copyTo(gzip, COPY_BUFFER_BYTES) }
      }
      val encryption = packed.inputStream().use { SegmentedCipher.encrypt(it, packed.length(), encrypted) }
      val snapshotId = UUID.randomUUID().toString()
      val count = index.count()
      val manifest = SnapshotManifest(
        snapshotId = snapshotId,
        createdAtMs = System.currentTimeMillis(),
        assetCount = count,
        libraryChatId = target.libraryChatId,
        systemChatId = target.systemChatId,
        dek = Base64.getEncoder().encodeToString(encryption.dek),
        compressed = true,
      )
      val sealed = VaultCrypto.seal(snapshotKey(key), json.encodeToString(manifest).toByteArray(), snapshotId.toByteArray())
      val caption = "$SNAPSHOT_PREFIX$snapshotId ${Base64.getUrlEncoder().withoutPadding().encodeToString(sealed)}"
      val document = withFloodRetry { client.sendDocument(target.systemChatId, encrypted.absolutePath, caption) }
      check(document.fileSize == encryption.header.encryptedSize) { "Telegram stored an incomplete index snapshot" }
      val older = snapshotMessages(target.systemChatId).map { it.getLong("id") }.filter { it != document.messageId }
      older.drop(SNAPSHOTS_TO_KEEP - 1).takeIf { it.isNotEmpty() }?.let { client.deleteMessages(target.systemChatId, it) }
      return count
    } finally {
      plain.delete()
      packed.delete()
      encrypted.delete()
    }
  }

  /**
   * New-phone restore: loads the newest index snapshot (if any), then reconciles it with the Library channel so
   * uploads made after the snapshot appear and assets deleted after it disappear. Returns the asset count.
   */
  suspend fun restoreIndex(): Long {
    val key = vault.requireKey()
    val target = channels.channels() ?: throw IllegalStateException("The vault channels are not set up yet")
    client.loadChats()
    val message = snapshotMessages(target.systemChatId).firstOrNull()
    if (message != null) {
      val caption = captionText(message)
      val separator = caption.indexOf(' ')
      val snapshotId = caption.substring(SNAPSHOT_PREFIX.length, separator)
      val sealed = Base64.getUrlDecoder().decode(caption.substring(separator + 1).trim())
      val manifest = json.decodeFromString<SnapshotManifest>(
        String(VaultCrypto.open(snapshotKey(key), sealed, snapshotId.toByteArray()))
      )
      val fileId = message.getJSONObject("content").getJSONObject("document").getJSONObject("document").getInt("id")
      val downloaded = File(client.downloadWhole(fileId))
      val decrypted = File(context.cacheDir, "keepsake-restore-$snapshotId.bin")
      val plain = File(context.cacheDir, "keepsake-restore-$snapshotId.db")
      try {
        decrypted.outputStream().use { SegmentedCipher.decrypt(Base64.getDecoder().decode(manifest.dek), downloaded, it) }
        if (manifest.compressed) {
          GZIPInputStream(decrypted.inputStream().buffered(COPY_BUFFER_BYTES)).use { gzip ->
            plain.outputStream().use { gzip.copyTo(it, COPY_BUFFER_BYTES) }
          }
        } else {
          decrypted.copyTo(plain, overwrite = true)
        }
        index.replaceWith(plain)
      } finally {
        decrypted.delete()
        plain.delete()
        downloaded.delete()
      }
    }
    reconcileWithHistory()
    // The phone that restores the vault becomes the one that writes to it; the old phone stops at its next check.
    claimVault()
    return index.count()
  }

  /**
   * Walks the whole Library channel: adds assets missing from the index (decoded from their encrypted recovery
   * captions), refreshes Telegram file ids and removes index rows whose message no longer exists.
   * Returns the number of assets added. Index writes are batched, so a library of 100k assets restores in minutes.
   */
  suspend fun reconcileWithHistory(): Long {
    val key = vault.requireKey()
    val target = channels.channels() ?: throw IllegalStateException("The vault channels are not set up yet")
    client.loadChats()
    val present = HashSet<Long>()
    val duplicates = mutableListOf<Pair<IndexRecord, List<PartRef>>>()
    val additions = LinkedHashMap<String, Pair<IndexRecord, List<PartRef>>>()
    val addedChecksums = HashSet<String>()
    val fileIdUpdates = HashMap<String, Int>()
    val splitParts = HashMap<String, MutableMap<Int, IndexRecord>>()
    var added = 0L

    fun flush() {
      index.upsertAll(additions.values.toList())
      additions.clear()
      addedChecksums.clear()
      index.updateFileIds(fileIdUpdates)
      fileIdUpdates.clear()
    }

    fun consider(record: IndexRecord, parts: List<PartRef>) {
      present += record.messageId
      if (record.id in additions || record.checksum in addedChecksums) {
        duplicates += record to parts
        return
      }
      val existing = index.find(record.id) ?: index.findByChecksum(record.checksum)
      when {
        existing == null -> {
          additions[record.id] = record to parts
          addedChecksums += record.checksum
          added++
        }
        existing.messageId == record.messageId -> if (existing.fileId != record.fileId) fileIdUpdates[existing.id] = record.fileId
        else -> duplicates += record to parts
      }
      if (additions.size >= RECONCILE_BATCH || fileIdUpdates.size >= RECONCILE_BATCH) flush()
    }

    scanHistory(target.libraryChatId) { message ->
      val entry = captionRecord(key, target.libraryChatId, message) ?: return@scanHistory
      if (entry.record.partCount > 1) {
        splitParts.getOrPut(entry.record.id) { HashMap() }[entry.partIndex] = entry.record
      } else {
        consider(entry.record, emptyList())
      }
    }
    // A split asset counts once every part is in the channel; one with parts missing is an unfinished upload.
    for (parts in splitParts.values) {
      val first = parts[0] ?: continue
      if ((0 until first.partCount).any { it !in parts }) continue
      val refs = (0 until first.partCount).map { part ->
        parts.getValue(part).let { PartRef(part, it.chatId, it.messageId, it.fileId, it.encryptedSize) }
      }
      consider(first.copy(encryptedSize = refs.sumOf { it.storedSize }), refs)
    }
    flush()

    val stale = index.messageRefs(target.libraryChatId).filter { it.second !in present }.map { it.first }
    if (stale.isNotEmpty()) {
      stale.forEach { thumbnails.delete(it) }
      index.delete(stale)
    }
    // A second copy of an asset whose indexed message is gone keeps the asset alive.
    for ((record, parts) in duplicates) {
      if (index.find(record.id) == null && index.findByChecksum(record.checksum) == null) {
        index.upsert(record, parts)
        added++
      }
    }
    return added
  }

  /** This install's random id. Kept outside the index, so a restored index never carries another phone's id. */
  val deviceId: String by lazy {
    val file = File(context.filesDir, "keepsake/device-id")
    file.takeIf { it.exists() }?.readText()?.trim()?.takeIf { it.isNotEmpty() }
      ?: UUID.randomUUID().toString().also {
        file.parentFile?.mkdirs()
        file.writeText(it)
      }
  }

  private val deviceName: String
    get() = listOf(Build.MANUFACTURER, Build.MODEL).filter { it.isNotBlank() }.distinct().joinToString(" ")
      .ifBlank { "another phone" }

  @Volatile
  private var writerCheckedAtMs = 0L

  /** The phone that currently owns the vault (newest valid claim in the System channel), or null before any claim. */
  suspend fun activeDevice(): DeviceClaim? {
    val key = vault.requireKey()
    val target = channels.channels() ?: return null
    return systemMessages(target.systemChatId)
      .filter { messageText(it).startsWith("$DEVICE_PREFIX ") }
      .sortedByDescending { it.getLong("id") }
      .firstNotNullOfOrNull { message -> runCatching { openClaim(key, messageText(message)) }.getOrNull() }
  }

  /** Makes this phone the one that writes to the vault. Other phones stop writing at their next check. */
  suspend fun claimVault(): DeviceClaim {
    val key = vault.requireKey()
    val target = channels.channels() ?: throw IllegalStateException("The vault channels are not set up yet")
    val claim = DeviceClaim(deviceId, deviceName, System.currentTimeMillis())
    val sealed = VaultCrypto.seal(deviceKey(key), json.encodeToString(claim).toByteArray(), DEVICE_PREFIX.toByteArray())
    val text = "$DEVICE_PREFIX ${Base64.getUrlEncoder().withoutPadding().encodeToString(sealed)}"
    val messageId = withFloodRetry { client.sendText(target.systemChatId, text) }
    val older = systemMessages(target.systemChatId)
      .filter { messageText(it).startsWith("$DEVICE_PREFIX ") }
      .map { it.getLong("id") }
      .filter { it != messageId }
    if (older.isNotEmpty()) runCatching { client.deleteMessages(target.systemChatId, older) }
    writerCheckedAtMs = System.currentTimeMillis()
    return claim
  }

  /**
   * Throws [VaultInUseException] when another phone has claimed the vault since this one did. The first write to a
   * vault without any claim claims it. A successful check is reused for [WRITER_CHECK_INTERVAL_MS] unless [fresh].
   */
  suspend fun ensureActiveWriter(fresh: Boolean = false) {
    if (!fresh && System.currentTimeMillis() - writerCheckedAtMs < WRITER_CHECK_INTERVAL_MS) return
    val holder = activeDevice()
    when {
      holder == null -> claimVault()
      holder.deviceId == deviceId -> writerCheckedAtMs = System.currentTimeMillis()
      else -> {
        writerCheckedAtMs = 0L
        throw VaultInUseException(holder)
      }
    }
  }

  fun indexBackupStatus(): IndexBackupState {
    val seq = index.currentSeq()
    val lastSeq = index.meta(META_SNAPSHOT_SEQ)?.toLongOrNull() ?: 0L
    return IndexBackupState(
      lastSnapshotAtMs = index.meta(META_SNAPSHOT_AT)?.toLongOrNull(),
      pendingChanges = (seq - lastSeq).coerceAtLeast(0),
      assetCount = index.count(),
      albumCount = index.albumCount(),
    )
  }

  private fun openClaim(key: ByteArray, text: String): DeviceClaim {
    val sealed = Base64.getUrlDecoder().decode(text.removePrefix("$DEVICE_PREFIX ").trim())
    return json.decodeFromString(String(VaultCrypto.open(deviceKey(key), sealed, DEVICE_PREFIX.toByteArray())))
  }

  private fun deviceKey(vaultKey: ByteArray) = VaultCrypto.subkey(vaultKey, "device")

  /** A Library channel message decoded from its recovery caption: an asset, or one part of a split asset. */
  private class CaptionEntry(val record: IndexRecord, val partIndex: Int)

  private fun captionRecord(key: ByteArray, chatId: Long, message: JSONObject): CaptionEntry? {
    val document = message.optJSONObject("content")?.optJSONObject("document")?.optJSONObject("document") ?: return null
    val record = runCatching { VaultCaption.decode(key, captionText(message)) }.getOrNull() ?: return null
    val encrypted = record.format != KeepsakeIndex.FORMAT_PLAIN
    val dek = if (encrypted) runCatching { Base64.getDecoder().decode(record.dek) }.getOrNull() ?: return null else null
    val split = record.partCount > 1
    if (split && (record.partBytes <= 0 || record.partBytes % SegmentedCipher.SEGMENT_SIZE != 0L || record.partIndex !in 0 until record.partCount)) {
      return null
    }
    return CaptionEntry(IndexRecord(
      id = record.assetId,
      checksum = Base64.getEncoder().encodeToString(hexToBytes(record.sha1)),
      localId = null,
      name = record.fileName,
      mimeType = record.mimeType,
      type = if (record.mimeType.startsWith("video/")) KeepsakeIndex.TYPE_VIDEO else KeepsakeIndex.TYPE_IMAGE,
      createdAtMs = record.takenAtEpochSec * 1000,
      modifiedAtMs = record.takenAtEpochSec * 1000,
      width = null,
      height = null,
      durationMs = null,
      sizeBytes = record.sizeBytes,
      latitude = null,
      longitude = null,
      make = null,
      model = null,
      orientation = null,
      isFavorite = false,
      visibility = 0,
      deletedAtMs = null,
      uploadedAtMs = message.optLong("date") * 1000,
      chatId = chatId,
      messageId = message.getLong("id"),
      fileId = document.getInt("id"),
      fileUniqueId = document.optJSONObject("remote")?.optString("unique_id").orEmpty(),
      encryptedSize = document.optLong("size"),
      wrappedDek = dek?.let { wrapDek(key, record.assetId, it) } ?: ByteArray(0),
      hasThumbnail = false,
      format = if (encrypted) KeepsakeIndex.FORMAT_ENCRYPTED else KeepsakeIndex.FORMAT_PLAIN,
      partCount = if (split) record.partCount else 1,
      partBytes = if (split) record.partBytes else 0,
    ), if (split) record.partIndex else 0)
  }

  private suspend fun systemMessages(systemChatId: Long): List<JSONObject> {
    val messages = mutableListOf<JSONObject>()
    scanHistory(systemChatId, limit = SYSTEM_SCAN_LIMIT) { messages += it }
    return messages
  }

  /** Index snapshots in the System channel, newest first. */
  private suspend fun snapshotMessages(systemChatId: Long): List<JSONObject> =
    systemMessages(systemChatId)
      .filter { it.optJSONObject("content")?.optString("@type") == "messageDocument" }
      .filter { captionText(it).startsWith(SNAPSHOT_PREFIX) }
      .sortedByDescending { it.getLong("id") }

  /**
   * Visits every message of [chatId], newest first, guarding against TDLib returning messages already seen.
   * Messages still being sent, or whose sending failed (an upload cut short by a killed app), exist only on this phone
   * and are skipped.
   */
  private suspend fun scanHistory(chatId: Long, limit: Int = Int.MAX_VALUE, visit: suspend (JSONObject) -> Unit) {
    val seen = HashSet<Long>()
    var fromMessageId = 0L
    while (seen.size < limit) {
      val fresh = withFloodRetry { client.history(chatId, fromMessageId, HISTORY_PAGE) }.filter { seen.add(it.getLong("id")) }
      if (fresh.isEmpty()) break
      for (message in fresh) if (message.optJSONObject("sending_state") == null) visit(message)
      fromMessageId = fresh.minOf { it.getLong("id") }
    }
  }

  private suspend fun render(record: IndexRecord): RenderedPreviews? {
    val file = reader.open(record)
    if (record.type == KeepsakeIndex.TYPE_VIDEO) {
      return LocalMediaReader.renderFromVideoSource(reader.mediaDataSource(file))
    }
    val temp = File(context.cacheDir, "keepsake-render-${record.id}")
    return try {
      temp.outputStream().buffered().use { copyPlaintext(file, it, 0, file.size - 1) }
      LocalMediaReader.renderFromFile(temp, isVideo = false)
    } finally {
      temp.delete()
    }
  }

  /**
   * Runs a Telegram request and waits out short flood waits (error 429 "retry after N"). A longer wait is not slept
   * through: it throws [FloodWaitException], and requests made before it ends fail at once, so a backup run stops
   * cleanly instead of failing every remaining file.
   */
  private suspend fun <T> withFloodRetry(block: suspend () -> T): T {
    var attempt = 0
    while (true) {
      val waitMs = floodUntilMs - System.currentTimeMillis()
      if (waitMs > MAX_INLINE_FLOOD_WAIT_S * 1000) throw FloodWaitException((waitMs + 999) / 1000)
      if (waitMs > 0) delay(waitMs)
      try {
        return block()
      } catch (error: TdException) {
        if (error.code != 429 || ++attempt > FLOOD_RETRIES) throw error
        val seconds = Regex("retry after (\\d+)").find(error.message)?.groupValues?.get(1)?.toLongOrNull() ?: 5
        floodUntilMs = maxOf(floodUntilMs, System.currentTimeMillis() + (seconds + 1) * 1000)
        if (seconds > MAX_INLINE_FLOOD_WAIT_S) throw FloodWaitException(seconds)
      }
    }
  }

  private fun wrapDek(vaultKey: ByteArray, assetId: String, dek: ByteArray) =
    VaultCrypto.seal(VaultCrypto.subkey(vaultKey, "dek"), dek, assetId.toByteArray())

  private fun unwrapDek(vaultKey: ByteArray, assetId: String, wrapped: ByteArray) =
    VaultCrypto.open(VaultCrypto.subkey(vaultKey, "dek"), wrapped, assetId.toByteArray())

  private fun snapshotKey(vaultKey: ByteArray) = VaultCrypto.subkey(vaultKey, "snapshot")

  private fun messageText(message: JSONObject): String =
    message.optJSONObject("content")?.optJSONObject("text")?.optString("text").orEmpty()

  private fun captionText(message: JSONObject): String =
    message.optJSONObject("content")?.optJSONObject("caption")?.optString("text").orEmpty()

  private fun hexToBytes(hex: String): ByteArray = ByteArray(hex.length / 2) { hex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

  companion object {
    private const val TAG = "AmbryLibrary"
    private const val MIB = 1024L * 1024
    /** Plain originals above this are split: Telegram takes files up to 2000 MiB (4000 MiB with Premium). */
    const val MAX_OBJECT_BYTES = 1_950L * MIB
    /** Original bytes per part of a split plain asset (a whole number of IMTG segments, like every part size). */
    const val PLAIN_PART_BYTES = 1_900L * MIB
    /**
     * Encrypted originals above this are split into [ENCRYPTED_PART_BYTES] parts although Telegram would take them
     * whole: a part needs little free space to prepare, and a background run that is stopped after a few minutes
     * keeps the parts it finished. Plain files stay whole up to [MAX_OBJECT_BYTES] so Telegram can play them.
     */
    const val SPLIT_ENCRYPTED_ABOVE_BYTES = 512L * MIB
    const val ENCRYPTED_PART_BYTES = 256L * MIB
    /** Free space kept on top of the staged copy (previews, Telegram's own temporary files). */
    private const val STAGING_HEADROOM_BYTES = 64L * MIB
    private const val MIN_UPLOAD_BYTES_PER_MS = 200L
    private const val MAX_INLINE_FLOOD_WAIT_S = 120L
    private const val META_PENDING_UPLOAD_PREFIX = "pending_upload:"
    private const val PENDING_UPLOAD_TTL_MS = 7L * 24 * 60 * 60 * 1000
    private const val RECONCILE_BATCH = 500
    const val VAULT_PREFIX = "KSVAULT1"
    const val DEVICE_PREFIX = "KSDEV1"
    private const val WRITER_CHECK_INTERVAL_MS = 10L * 60 * 1000
    const val SNAPSHOT_PREFIX = "KSIDX1:"
    /** System channel titles: current vaults, then vaults created before the app was renamed. */
    val SYSTEM_TITLE_PREFIXES = listOf("Ambry System", "Keepsake System")
    private const val SNAPSHOTS_TO_KEEP = 3
    private const val FLOOD_RETRIES = 5
    private const val HISTORY_PAGE = 100
    private const val SNAPSHOT_INTERVAL_MS = 6L * 60 * 60 * 1000
    private const val TRASH_RETENTION_MS = 30L * 24 * 60 * 60 * 1000
    private const val SNAPSHOT_CHANGE_THRESHOLD = 200L
    /** A library of n assets snapshots after n / this many changes (if that is above [SNAPSHOT_CHANGE_THRESHOLD]). */
    private const val SNAPSHOT_CHANGE_DIVISOR = 20L
    private const val META_SNAPSHOT_SEQ = "last_snapshot_seq"
    private const val META_SNAPSHOT_AT = "last_snapshot_at"
    private const val META_VAULT_PUBLISHED = "vault_record_published_at"
    private const val META_ENCRYPT_UPLOADS = "encrypt_uploads"
    private const val ALBUM_SNAPSHOT_SPACING_MS = 60_000L
    private const val COPY_BUFFER_BYTES = 256 * 1024
    private const val MAX_FILE_NAME_CHARS = 180
    private val UNSAFE_FILE_NAME_CHARS = Regex("[\\\\/:*?\"<>|\u0000-\u001f]")
    private const val DEFAULT_VAULT_NAME = "My Vault"
    private const val SYSTEM_SCAN_LIMIT = 500
  }
}
