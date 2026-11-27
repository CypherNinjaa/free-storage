package app.alextran.immich.keepsake

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.Base64

@Serializable
data class RecoveryRecord(
  val assetId: String,
  val sha1: String,
  val takenAtEpochSec: Long,
  val sizeBytes: Long,
  val mimeType: String,
  val fileName: String,
  /** Base64 per-file key; empty for files stored without encryption. */
  val dek: String,
  /** [KeepsakeIndex.FORMAT_ENCRYPTED] or [KeepsakeIndex.FORMAT_PLAIN]; older records omit it (encrypted). */
  val format: Int = KeepsakeIndex.FORMAT_ENCRYPTED,
  /** Assets larger than one Telegram file are split (see [PartLayout]); every part's caption names its part. */
  val partIndex: Int = 0,
  val partCount: Int = 1,
  /** Original bytes per part; 0 for assets stored in one file. */
  val partBytes: Long = 0,
)

object VaultCaption {
  const val PREFIX = "IMTG2:"
  private const val MAX_FILE_NAME_CHARS = 120
  private val json = Json { ignoreUnknownKeys = true }

  fun searchToken(assetId: String): String = "$PREFIX$assetId"

  fun encode(vaultKey: ByteArray, record: RecoveryRecord): String {
    val bounded = record.copy(fileName = record.fileName.take(MAX_FILE_NAME_CHARS))
    val sealed = VaultCrypto.seal(captionKey(vaultKey), json.encodeToString(bounded).toByteArray(), bounded.assetId.toByteArray())
    return "${searchToken(bounded.assetId)} ${Base64.getUrlEncoder().withoutPadding().encodeToString(sealed)}"
  }

  fun decode(vaultKey: ByteArray, caption: String): RecoveryRecord? {
    if (!caption.startsWith(PREFIX)) return null
    val separator = caption.indexOf(' ')
    if (separator <= PREFIX.length) return null
    val assetId = caption.substring(PREFIX.length, separator)
    val sealed = Base64.getUrlDecoder().decode(caption.substring(separator + 1).trim())
    val record = json.decodeFromString<RecoveryRecord>(String(VaultCrypto.open(captionKey(vaultKey), sealed, assetId.toByteArray())))
    return record.takeIf { it.assetId == assetId }
  }

  private fun captionKey(vaultKey: ByteArray): ByteArray = VaultCrypto.subkey(vaultKey, "caption")
}
