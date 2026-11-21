package app.alextran.immich.keepsake

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

interface DeviceKeyWrapper {
  fun wrap(plaintext: ByteArray): ByteArray

  fun unwrap(wrapped: ByteArray): ByteArray
}

class AndroidKeystoreKeyWrapper(private val alias: String) : DeviceKeyWrapper {
  private val keyStore: KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

  @Synchronized
  private fun secretKey(): SecretKey {
    (keyStore.getEntry(alias, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
    val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
    generator.init(
      KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .setKeySize(256)
        .build()
    )
    return generator.generateKey()
  }

  override fun wrap(plaintext: ByteArray): ByteArray {
    val cipher = Cipher.getInstance(TRANSFORMATION)
    cipher.init(Cipher.ENCRYPT_MODE, secretKey())
    val iv = cipher.iv
    return byteArrayOf(iv.size.toByte()) + iv + cipher.doFinal(plaintext)
  }

  override fun unwrap(wrapped: ByteArray): ByteArray {
    val ivLength = wrapped[0].toInt()
    val cipher = Cipher.getInstance(TRANSFORMATION)
    cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, wrapped, 1, ivLength))
    return cipher.doFinal(wrapped, 1 + ivLength, wrapped.size - 1 - ivLength)
  }

  private companion object {
    const val KEYSTORE = "AndroidKeyStore"
    const val TRANSFORMATION = "AES/GCM/NoPadding"
  }
}
