package app.alextran.immich.keepsake

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import javax.crypto.AEADBadTagException

class VaultCryptoTest {
  private val fastKdf = KdfParams(memoryKib = 1024, iterations = 1, parallelism = 1)

  @Test
  fun hkdfMatchesRfc5869TestCase1() {
    val ikm = ByteArray(22) { 0x0b }
    val salt = ByteArray(13) { it.toByte() }
    val info = ByteArray(10) { (0xf0 + it).toByte() }
    val okm = VaultCrypto.hkdfSha256(ikm, salt, info, 42)
    assertEquals(
      "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865",
      okm.toHex(),
    )
  }

  @Test
  fun hkdfMatchesRfc5869TestCase3WithEmptySaltAndInfo() {
    val ikm = ByteArray(22) { 0x0b }
    val okm = VaultCrypto.hkdfSha256(ikm, ByteArray(0), ByteArray(0), 42)
    assertEquals(
      "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8",
      okm.toHex(),
    )
  }

  @Test
  fun sealedDataOpensOnlyWithSameKeyAndAad() {
    val key = VaultCrypto.randomBytes(32)
    val sealed = VaultCrypto.seal(key, "hello".toByteArray(), "aad".toByteArray())
    assertArrayEquals("hello".toByteArray(), VaultCrypto.open(key, sealed, "aad".toByteArray()))
    assertThrowsBadTag { VaultCrypto.open(key, sealed, "other".toByteArray()) }
    assertThrowsBadTag { VaultCrypto.open(VaultCrypto.randomBytes(32), sealed, "aad".toByteArray()) }
  }

  @Test
  fun sealingTwiceUsesFreshNonces() {
    val key = VaultCrypto.randomBytes(32)
    val first = VaultCrypto.seal(key, ByteArray(16), ByteArray(0))
    val second = VaultCrypto.seal(key, ByteArray(16), ByteArray(0))
    assertFalse(first.contentEquals(second))
  }

  @Test
  fun subkeysDifferPerPurpose() {
    val vaultKey = VaultCrypto.randomBytes(32)
    assertFalse(VaultCrypto.subkey(vaultKey, "caption").contentEquals(VaultCrypto.subkey(vaultKey, "index")))
    assertArrayEquals(VaultCrypto.subkey(vaultKey, "caption"), VaultCrypto.subkey(vaultKey, "caption"))
  }

  @Test
  fun passphraseDerivationIsDeterministicPerSalt() {
    val salt = VaultCrypto.randomBytes(16)
    val first = VaultCrypto.deriveKeyFromPassphrase("correct horse", salt, fastKdf)
    assertArrayEquals(first, VaultCrypto.deriveKeyFromPassphrase("correct horse", salt, fastKdf))
    assertFalse(first.contentEquals(VaultCrypto.deriveKeyFromPassphrase("correct horse", VaultCrypto.randomBytes(16), fastKdf)))
    assertFalse(first.contentEquals(VaultCrypto.deriveKeyFromPassphrase("wrong horse", salt, fastKdf)))
  }

  @Test(expected = IllegalArgumentException::class)
  fun recoveryEntropyMustBe24Bytes() {
    VaultCrypto.deriveKeyFromRecoveryEntropy(ByteArray(16), VaultCrypto.randomBytes(16))
  }

  private fun assertThrowsBadTag(block: () -> Unit) {
    try {
      block()
      throw AssertionError("Expected AEADBadTagException")
    } catch (expected: AEADBadTagException) {
    }
  }
}
