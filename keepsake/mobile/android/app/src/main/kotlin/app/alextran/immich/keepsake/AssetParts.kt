package app.alextran.immich.keepsake

import kotlinx.serialization.Serializable

/**
 * How an asset too big for one Telegram file is stored: cut into parts that each hold [partPlainBytes] of the
 * original (the last part holds the rest).
 *
 * The parts of an encrypted asset are one IMTG stream (header + segments, exactly what [SegmentedCipher.encrypt]
 * writes) cut at segment boundaries, with the header in part 0. Segments keep their position in the whole stream,
 * so swapping or reordering parts fails authentication. The parts of a plain asset are byte ranges of the original.
 * Either way every segment (or plain 1 MiB block) is read from a single part.
 */
class PartLayout(val plainSize: Long, val partPlainBytes: Long, val encrypted: Boolean) {
  init {
    require(plainSize >= 0) { "Invalid size $plainSize" }
    require(partPlainBytes > 0 && partPlainBytes % SegmentedCipher.SEGMENT_SIZE == 0L) {
      "Part size $partPlainBytes is not a whole number of segments"
    }
  }

  private val segmentsPerPart: Long = partPlainBytes / SegmentedCipher.SEGMENT_SIZE

  /** Stored size of a full encrypted part after part 0 (part 0 also holds the header). */
  private val fullEncryptedPart: Long = partPlainBytes + segmentsPerPart * SegmentedCipher.TAG_BYTES

  val partCount: Int = if (plainSize == 0L) 1 else ((plainSize + partPlainBytes - 1) / partPlainBytes).toInt()

  fun plainStart(part: Int): Long = checkPart(part) * partPlainBytes

  fun plainEnd(part: Int): Long = minOf(plainSize, (checkPart(part) + 1L) * partPlainBytes)

  fun firstSegment(part: Int): Long = checkPart(part) * segmentsPerPart

  fun segmentCount(part: Int): Long {
    val plain = plainEnd(part) - plainStart(part)
    return (plain + SegmentedCipher.SEGMENT_SIZE - 1) / SegmentedCipher.SEGMENT_SIZE
  }

  /** Size of part [part] as stored in Telegram. */
  fun storedSize(part: Int): Long {
    val plain = plainEnd(part) - plainStart(part)
    if (!encrypted) return plain
    return plain + segmentCount(part) * SegmentedCipher.TAG_BYTES + if (part == 0) SegmentedCipher.HEADER_SIZE else 0
  }

  /** Total stored size: for encrypted assets this equals the IMTG header's encrypted size. */
  val totalStoredSize: Long get() = (0 until partCount).sumOf { storedSize(it) }

  /** The part holding byte [offset] of the stored stream, and the offset inside that part. */
  fun locate(offset: Long): Pair<Int, Long> {
    require(offset >= 0) { "Invalid offset $offset" }
    if (partCount == 1) return 0 to offset
    if (!encrypted) {
      val part = minOf(offset / partPlainBytes, partCount - 1L).toInt()
      return part to offset - part * partPlainBytes
    }
    val partZeroSize = SegmentedCipher.HEADER_SIZE + fullEncryptedPart
    if (offset < partZeroSize) return 0 to offset
    val part = minOf((offset - SegmentedCipher.HEADER_SIZE) / fullEncryptedPart, partCount - 1L).toInt()
    return part to offset - (SegmentedCipher.HEADER_SIZE + part * fullEncryptedPart)
  }

  private fun checkPart(part: Int): Long {
    require(part in 0 until partCount) { "Part $part is out of range" }
    return part.toLong()
  }
}

/** One Telegram message holding part [index] of a split asset. */
data class PartRef(val index: Int, val chatId: Long, val messageId: Long, val fileId: Int, val storedSize: Long)

/** A part of a split upload that is already in Telegram. */
@Serializable
data class UploadedPart(
  val index: Int,
  val chatId: Long,
  val messageId: Long,
  val fileId: Int,
  val fileUniqueId: String,
  val storedSize: Long,
)

/**
 * A split upload that has not finished, kept in the index so the next attempt continues after the parts already in
 * Telegram instead of starting again. It keeps the asset id, the wrapped file key and the IMTG nonce, so resumed
 * parts are byte-for-byte what the first attempt would have sent; [partSha1] makes sure the original is unchanged.
 */
@Serializable
data class PendingUpload(
  val assetId: String,
  val checksum: String,
  val plainSize: Long,
  val partBytes: Long,
  val format: Int,
  /** Base64 file key sealed with the vault key (empty for plain uploads). */
  val wrappedDek: String,
  /** Base64 base nonce of the IMTG header (empty for plain uploads). */
  val baseNonce: String,
  /** SHA-1 (hex) of the original bytes of each part. */
  val partSha1: List<String>,
  val uploaded: List<UploadedPart>,
  val updatedAtMs: Long,
)
