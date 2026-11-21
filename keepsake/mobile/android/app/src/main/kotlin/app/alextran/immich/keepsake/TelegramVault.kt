package app.alextran.immich.keepsake

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID

@Serializable
data class ChannelState(val libraryChatId: Long, val systemChatId: Long)

class TelegramVault(
  private val directory: File,
  private val cacheDirectory: File,
  private val client: TdClient,
  private val vaultStore: VaultStore,
) {
  private val stateFile = File(directory, "telegram.json")
  private val json = Json { ignoreUnknownKeys = true }

  fun channels(): ChannelState? =
    if (stateFile.exists()) json.decodeFromString<ChannelState>(stateFile.readText()).takeIf { it.isComplete } else null

  suspend fun ensureChannels(vaultName: String): ChannelState {
    val name = vaultName.trim().ifBlank { DEFAULT_VAULT_NAME }.take(64)
    val saved = if (stateFile.exists()) json.decodeFromString<ChannelState>(stateFile.readText()) else null
    val library = saved?.libraryChatId?.takeIf { it != 0L && client.chatExists(it) }
      ?: client.createPrivateChannel("Ambry Library · $name", LIBRARY_DESCRIPTION)
    persist(ChannelState(library, saved?.systemChatId ?: 0L))
    val system = saved?.systemChatId?.takeIf { it != 0L && client.chatExists(it) }
      ?: client.createPrivateChannel("Ambry System · $name", SYSTEM_DESCRIPTION)
    return ChannelState(library, system).also(::persist)
  }

  suspend fun runSelfTest(report: MutableList<String>) {
    val vaultKey = vaultStore.requireKey()
    val channels = channels() ?: throw IllegalStateException("Vault channels are not set up yet")
    val plaintext = File(cacheDirectory, "keepsake-self-test.bin")
    val encrypted = File(cacheDirectory, "keepsake-self-test.imtg")
    var uploaded: UploadedDocument? = null
    try {
      var started = System.currentTimeMillis()
      val size = SegmentedCipher.SEGMENT_SIZE + 256 * 1024
      plaintext.writeBytes(VaultCrypto.randomBytes(size))
      val encryption = plaintext.inputStream().use { SegmentedCipher.encrypt(it, size.toLong(), encrypted) }
      report.pass("Encrypted ${size / 1024} KiB into ${encryption.header.segmentCount} segments", started)

      val assetId = "self-test-${UUID.randomUUID()}"
      val caption = VaultCaption.encode(
        vaultKey,
        RecoveryRecord(
          assetId = assetId,
          sha1 = encryption.plaintextSha1,
          takenAtEpochSec = System.currentTimeMillis() / 1000,
          sizeBytes = size.toLong(),
          mimeType = "application/octet-stream",
          fileName = "self-test.bin",
          dek = Base64.getEncoder().encodeToString(encryption.dek),
        ),
      )
      started = System.currentTimeMillis()
      val document = client.sendDocument(channels.systemChatId, encrypted.absolutePath, caption)
      uploaded = document
      check(document.fileSize == encryption.header.encryptedSize) {
        "Telegram stored ${document.fileSize} bytes, expected ${encryption.header.encryptedSize}"
      }
      report.pass("Uploaded to the System channel as message ${document.messageId}", started)
      plaintext.delete()
      encrypted.delete()

      started = System.currentTimeMillis()
      val message = client.getMessages(channels.systemChatId, listOf(document.messageId)).single()
        ?: throw IllegalStateException("Uploaded message was not found")
      report.pass("Message confirmed with getMessages", started)

      started = System.currentTimeMillis()
      check(document.messageId in client.searchMessageIds(channels.systemChatId, VaultCaption.searchToken(assetId))) {
        "Caption search did not return the uploaded message"
      }
      report.pass("Message found by caption search", started)

      started = System.currentTimeMillis()
      val record = VaultCaption.decode(vaultKey, captionText(message))
        ?: throw IllegalStateException("Recovery caption could not be decoded")
      check(record.sha1 == encryption.plaintextSha1) { "Recovery caption checksum mismatch" }
      report.pass("Recovery caption decrypted", started)

      started = System.currentTimeMillis()
      val header = SegmentedCipher.Header.parse(client.downloadRange(document.fileId, 0, SegmentedCipher.HEADER_SIZE))
      val dek = Base64.getDecoder().decode(record.dek)
      val sha1 = MessageDigest.getInstance("SHA-1")
      for (index in 0 until header.segmentCount) {
        val ciphertext = client.downloadRange(document.fileId, header.segmentOffset(index), header.segmentEncryptedLength(index))
        sha1.update(SegmentedCipher.decryptSegment(dek, header, index, ciphertext))
      }
      check(sha1.digest().toHex() == encryption.plaintextSha1) { "Downloaded content does not match the original" }
      report.pass("Downloaded ${header.segmentCount} segments by range, decrypted, SHA-1 matches", started)
    } finally {
      plaintext.delete()
      encrypted.delete()
      uploaded?.let { document ->
        val started = System.currentTimeMillis()
        runCatching { client.deleteMessages(document.chatId, listOf(document.messageId)) }
          .onSuccess { report.pass("Test message deleted", started) }
          .onFailure { report += "✗ Test message could not be deleted: ${it.message}" }
      }
    }
  }

  fun adopt(state: ChannelState) = persist(state)

  private fun persist(state: ChannelState) {
    directory.mkdirs()
    stateFile.writeText(json.encodeToString(state))
  }

  private fun captionText(message: JSONObject): String =
    message.getJSONObject("content").optJSONObject("caption")?.optString("text").orEmpty()

  private fun MutableList<String>.pass(step: String, startedAt: Long) {
    add("✓ $step (${System.currentTimeMillis() - startedAt} ms)")
  }

  private val ChannelState.isComplete: Boolean
    get() = libraryChatId != 0L && systemChatId != 0L

  private companion object {
    const val DEFAULT_VAULT_NAME = "My Vault"
    const val LIBRARY_DESCRIPTION = "Ambry photo library. Managed by the Ambry app — do not post or delete here."
    const val SYSTEM_DESCRIPTION = "Encrypted Ambry library index backups. Managed by the Ambry app — do not post or delete here."
  }
}
