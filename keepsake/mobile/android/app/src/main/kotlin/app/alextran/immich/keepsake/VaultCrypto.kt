package app.alextran.immich.keepsake

import kotlinx.serialization.Serializable
import org.bouncycastle.crypto.generators.Argon2BytesGenerator
import org.bouncycastle.crypto.params.Argon2Parameters
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

@Serializable
data class KdfParams(val memoryKib: Int, val iterations: Int, val parallelism: Int) {
  companion object {
    val DEFAULT = KdfParams(memoryKib = 65536, iterations = 3, parallelism = 2)
  }
}

object VaultCrypto {
  const val KEY_BYTES = 32
  const val SALT_BYTES = 16
  const val RECOVERY_ENTROPY_BYTES = 24
  private const val NONCE_BYTES = 12
  private const val TAG_BITS = 128
  private const val HMAC = "HmacSHA256"
  private val random = SecureRandom()

  fun randomBytes(size: Int): ByteArray = ByteArray(size).also(random::nextBytes)

  fun deriveKeyFromPassphrase(passphrase: String, salt: ByteArray, params: KdfParams): ByteArray {
    val generator = Argon2BytesGenerator()
    generator.init(
      Argon2Parameters.Builder(Argon2Parameters.ARGON2_id)
        .withVersion(Argon2Parameters.ARGON2_VERSION_13)
        .withSalt(salt)
        .withMemoryAsKB(params.memoryKib)
        .withIterations(params.iterations)
        .withParallelism(params.parallelism)
        .build()
    )
    val key = ByteArray(KEY_BYTES)
    generator.generateBytes(passphrase.toByteArray(Charsets.UTF_8), key)
    return key
  }

  fun deriveKeyFromRecoveryEntropy(entropy: ByteArray, salt: ByteArray): ByteArray {
    require(entropy.size == RECOVERY_ENTROPY_BYTES) { "Recovery entropy must be $RECOVERY_ENTROPY_BYTES bytes" }
    return hkdfSha256(entropy, salt, "keepsake/recovery-kek/v1".toByteArray(), KEY_BYTES)
  }

  fun subkey(vaultKey: ByteArray, purpose: String): ByteArray =
    hkdfSha256(vaultKey, ByteArray(0), "keepsake/$purpose/v1".toByteArray(), KEY_BYTES)

  fun seal(key: ByteArray, plaintext: ByteArray, aad: ByteArray): ByteArray {
    val nonce = randomBytes(NONCE_BYTES)
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
    cipher.updateAAD(aad)
    return nonce + cipher.doFinal(plaintext)
  }

  fun open(key: ByteArray, sealed: ByteArray, aad: ByteArray): ByteArray {
    require(sealed.size > NONCE_BYTES) { "Sealed payload is too short" }
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, sealed, 0, NONCE_BYTES))
    cipher.updateAAD(aad)
    return cipher.doFinal(sealed, NONCE_BYTES, sealed.size - NONCE_BYTES)
  }

  fun hkdfSha256(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
    val mac = Mac.getInstance(HMAC)
    mac.init(SecretKeySpec(if (salt.isEmpty()) ByteArray(mac.macLength) else salt, HMAC))
    val pseudoRandomKey = mac.doFinal(ikm)
    mac.init(SecretKeySpec(pseudoRandomKey, HMAC))
    val output = ByteArray(length)
    var block = ByteArray(0)
    var written = 0
    var counter = 1
    while (written < length) {
      mac.update(block)
      mac.update(info)
      mac.update(counter.toByte())
      block = mac.doFinal()
      val take = minOf(block.size, length - written)
      System.arraycopy(block, 0, output, written, take)
      written += take
      counter++
    }
    return output
  }
}
