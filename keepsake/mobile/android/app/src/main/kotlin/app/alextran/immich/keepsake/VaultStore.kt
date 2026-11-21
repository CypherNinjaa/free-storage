package app.alextran.immich.keepsake

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.util.Base64
import java.util.UUID

@Serializable
data class VaultDescriptor(
  val version: Int,
  val vaultId: String,
  val createdAtEpochMs: Long,
  val kdf: KdfParams,
  val passphraseSalt: String,
  val passphraseWrappedKey: String,
  val recoverySalt: String,
  val recoveryWrappedKey: String,
)

class VaultLockedException : IllegalStateException("The vault is locked")

class VaultStore(
  private val directory: File,
  private val deviceKeyWrapper: DeviceKeyWrapper,
  private val kdfParams: KdfParams = KdfParams.DEFAULT,
) {
  private val descriptorFile = File(directory, "vault.json")
  private val deviceCacheFile = File(directory, "vault-device.bin")
  private val json = Json { ignoreUnknownKeys = true }

  @Volatile
  private var vaultKey: ByteArray? = null

  val exists: Boolean
    get() = descriptorFile.exists()

  val isUnlocked: Boolean
    get() = vaultKey != null

  fun vaultId(): String? = descriptor()?.vaultId

  fun descriptorJson(): String? = if (exists) descriptorFile.readText() else null

  @Synchronized
  fun importDescriptor(descriptorJson: String) {
    json.decodeFromString<VaultDescriptor>(descriptorJson)
    directory.mkdirs()
    writeAtomically(descriptorFile, descriptorJson.toByteArray())
    lock()
  }

  @Synchronized
  fun create(passphrase: String, recoveryEntropy: ByteArray): String {
    check(!exists) { "A vault already exists on this device" }
    val key = VaultCrypto.randomBytes(VaultCrypto.KEY_BYTES)
    val vaultId = UUID.randomUUID().toString()
    val passphraseSalt = VaultCrypto.randomBytes(VaultCrypto.SALT_BYTES)
    val recoverySalt = VaultCrypto.randomBytes(VaultCrypto.SALT_BYTES)
    val passphraseKey = VaultCrypto.deriveKeyFromPassphrase(passphrase, passphraseSalt, kdfParams)
    val recoveryKey = VaultCrypto.deriveKeyFromRecoveryEntropy(recoveryEntropy, recoverySalt)
    val descriptor = VaultDescriptor(
      version = 1,
      vaultId = vaultId,
      createdAtEpochMs = System.currentTimeMillis(),
      kdf = kdfParams,
      passphraseSalt = passphraseSalt.encode(),
      passphraseWrappedKey = VaultCrypto.seal(passphraseKey, key, wrapAad(vaultId, PASSPHRASE)).encode(),
      recoverySalt = recoverySalt.encode(),
      recoveryWrappedKey = VaultCrypto.seal(recoveryKey, key, wrapAad(vaultId, RECOVERY)).encode(),
    )
    directory.mkdirs()
    writeAtomically(descriptorFile, json.encodeToString(descriptor).toByteArray())
    remember(key)
    return vaultId
  }

  @Synchronized
  fun unlockWithPassphrase(passphrase: String) {
    val descriptor = requireDescriptor()
    val kek = VaultCrypto.deriveKeyFromPassphrase(passphrase, descriptor.passphraseSalt.decode(), descriptor.kdf)
    remember(VaultCrypto.open(kek, descriptor.passphraseWrappedKey.decode(), wrapAad(descriptor.vaultId, PASSPHRASE)))
  }

  @Synchronized
  fun unlockWithRecoveryEntropy(recoveryEntropy: ByteArray) {
    val descriptor = requireDescriptor()
    val kek = VaultCrypto.deriveKeyFromRecoveryEntropy(recoveryEntropy, descriptor.recoverySalt.decode())
    remember(VaultCrypto.open(kek, descriptor.recoveryWrappedKey.decode(), wrapAad(descriptor.vaultId, RECOVERY)))
  }

  @Synchronized
  fun restoreFromDevice(): Boolean {
    if (vaultKey != null) return true
    if (!exists || !deviceCacheFile.exists()) return false
    return runCatching { vaultKey = deviceKeyWrapper.unwrap(deviceCacheFile.readBytes()) }.isSuccess
  }

  @Synchronized
  fun lock() {
    vaultKey?.fill(0)
    vaultKey = null
    deviceCacheFile.delete()
  }

  fun requireKey(): ByteArray = vaultKey ?: throw VaultLockedException()

  private fun remember(key: ByteArray) {
    vaultKey = key
    writeAtomically(deviceCacheFile, deviceKeyWrapper.wrap(key))
  }

  private fun descriptor(): VaultDescriptor? =
    if (exists) json.decodeFromString<VaultDescriptor>(descriptorFile.readText()) else null

  private fun requireDescriptor(): VaultDescriptor = descriptor() ?: throw IllegalStateException("No vault on this device")

  private fun wrapAad(vaultId: String, method: String): ByteArray = "keepsake/vault-key/v1|$vaultId|$method".toByteArray()

  private fun writeAtomically(target: File, bytes: ByteArray) {
    val temp = File(target.parentFile, "${target.name}.tmp")
    temp.writeBytes(bytes)
    check(temp.renameTo(target) || (target.delete() && temp.renameTo(target))) { "Could not write ${target.name}" }
  }

  private fun ByteArray.encode(): String = Base64.getEncoder().encodeToString(this)

  private fun String.decode(): ByteArray = Base64.getDecoder().decode(this)

  private companion object {
    const val PASSPHRASE = "passphrase"
    const val RECOVERY = "recovery"
  }
}
