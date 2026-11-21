package app.alextran.immich.keepsake

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import javax.crypto.AEADBadTagException

class VaultStoreTest {
  @get:Rule
  val folder = TemporaryFolder()

  private val fastKdf = KdfParams(memoryKib = 1024, iterations = 1, parallelism = 1)
  private val entropy = ByteArray(VaultCrypto.RECOVERY_ENTROPY_BYTES) { (it * 7).toByte() }

  @Test
  fun passphraseAndRecoveryWordsUnlockTheSameVaultKey() {
    val directory = folder.newFolder()
    val created = store(directory)
    val vaultId = created.create("long passphrase", entropy)
    val key = created.requireKey().copyOf()

    val byPassphrase = store(directory).apply { unlockWithPassphrase("long passphrase") }
    val byRecovery = store(directory).apply { unlockWithRecoveryEntropy(entropy) }

    assertEquals(vaultId, byPassphrase.vaultId())
    assertArrayEquals(key, byPassphrase.requireKey())
    assertArrayEquals(key, byRecovery.requireKey())
  }

  @Test(expected = AEADBadTagException::class)
  fun wrongPassphraseIsRejected() {
    val directory = folder.newFolder()
    store(directory).create("long passphrase", entropy)
    store(directory).unlockWithPassphrase("not the passphrase")
  }

  @Test(expected = AEADBadTagException::class)
  fun wrongRecoveryWordsAreRejected() {
    val directory = folder.newFolder()
    store(directory).create("long passphrase", entropy)
    store(directory).unlockWithRecoveryEntropy(ByteArray(VaultCrypto.RECOVERY_ENTROPY_BYTES))
  }

  @Test
  fun deviceCacheRestoresUntilLocked() {
    val directory = folder.newFolder()
    val created = store(directory)
    created.create("long passphrase", entropy)
    val key = created.requireKey().copyOf()

    val restarted = store(directory)
    assertTrue(restarted.restoreFromDevice())
    assertArrayEquals(key, restarted.requireKey())

    restarted.lock()
    assertFalse(restarted.isUnlocked)
    assertFalse(store(directory).restoreFromDevice())
  }

  @Test(expected = VaultLockedException::class)
  fun lockedVaultRefusesKeyAccess() {
    store(folder.newFolder()).requireKey()
  }

  @Test(expected = IllegalStateException::class)
  fun aVaultCannotBeCreatedTwice() {
    val directory = folder.newFolder()
    store(directory).create("long passphrase", entropy)
    store(directory).create("another passphrase", entropy)
  }

  @Test
  fun captionsRoundTripWithTheVaultKey() {
    val key = VaultCrypto.randomBytes(32)
    val record = RecoveryRecord("asset-1", "abc", 1_700_000_000, 42, "image/jpeg", "x".repeat(400), "ZGVr")
    val caption = VaultCaption.encode(key, record)

    assertTrue(caption.startsWith(VaultCaption.searchToken("asset-1") + " "))
    assertTrue(caption.length < 1024)
    assertEquals(record.copy(fileName = "x".repeat(120)), VaultCaption.decode(key, caption))
    assertNull(VaultCaption.decode(key, "unrelated caption"))
  }

  @Test(expected = AEADBadTagException::class)
  fun captionsBoundToTheirAssetId() {
    val key = VaultCrypto.randomBytes(32)
    val caption = VaultCaption.encode(key, RecoveryRecord("asset-1", "abc", 0, 1, "image/jpeg", "a.jpg", "ZGVr"))
    VaultCaption.decode(key, caption.replaceFirst("asset-1", "asset-2"))
  }

  private fun store(directory: java.io.File) = VaultStore(directory, FakeDeviceKeyWrapper, fastKdf)

  private object FakeDeviceKeyWrapper : DeviceKeyWrapper {
    private val deviceKey = VaultCrypto.randomBytes(32)

    override fun wrap(plaintext: ByteArray): ByteArray = VaultCrypto.seal(deviceKey, plaintext, ByteArray(0))

    override fun unwrap(wrapped: ByteArray): ByteArray = VaultCrypto.open(deviceKey, wrapped, ByteArray(0))
  }
}
