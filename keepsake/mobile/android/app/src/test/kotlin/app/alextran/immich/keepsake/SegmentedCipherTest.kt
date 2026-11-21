package app.alextran.immich.keepsake

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import javax.crypto.AEADBadTagException

class SegmentedCipherTest {
  @get:Rule
  val folder = TemporaryFolder()

  private val segment = SegmentedCipher.SEGMENT_SIZE

  @Test
  fun roundTripsAcrossSegmentBoundaries() {
    for (size in listOf(0, 1, segment - 1, segment, segment + 1, 3 * segment + 17)) {
      val plaintext = VaultCrypto.randomBytes(size)
      val encrypted = folder.newFile()
      val result = SegmentedCipher.encrypt(plaintext.inputStream(), size.toLong(), encrypted)

      assertEquals(sha1(plaintext), result.plaintextSha1)
      assertEquals(result.header.encryptedSize, encrypted.length())

      val output = ByteArrayOutputStream()
      assertEquals(sha1(plaintext), SegmentedCipher.decrypt(result.dek, encrypted, output))
      assertArrayEquals(plaintext, output.toByteArray())
    }
  }

  @Test
  fun decryptsASingleSegmentByRange() {
    val plaintext = VaultCrypto.randomBytes(2 * segment + 5)
    val encrypted = folder.newFile()
    val result = SegmentedCipher.encrypt(plaintext.inputStream(), plaintext.size.toLong(), encrypted)
    val header = SegmentedCipher.Header.parse(encrypted.readBytes().copyOfRange(0, SegmentedCipher.HEADER_SIZE))

    val ciphertext = readRange(encrypted, header.segmentOffset(2), header.segmentEncryptedLength(2))
    val decrypted = SegmentedCipher.decryptSegment(result.dek, header, 2, ciphertext)

    assertArrayEquals(plaintext.copyOfRange(2 * segment, plaintext.size), decrypted)
  }

  @Test(expected = AEADBadTagException::class)
  fun detectsTamperedCiphertext() {
    val encrypted = folder.newFile()
    val result = SegmentedCipher.encrypt(VaultCrypto.randomBytes(1000).inputStream(), 1000, encrypted)
    RandomAccessFile(encrypted, "rw").use { raf ->
      raf.seek(SegmentedCipher.HEADER_SIZE + 10L)
      val original = raf.read()
      raf.seek(SegmentedCipher.HEADER_SIZE + 10L)
      raf.write(original xor 0x01)
    }
    SegmentedCipher.decrypt(result.dek, encrypted, ByteArrayOutputStream())
  }

  @Test(expected = AEADBadTagException::class)
  fun rejectsSegmentsSwappedBetweenPositions() {
    val plaintext = VaultCrypto.randomBytes(2 * segment)
    val encrypted = folder.newFile()
    val result = SegmentedCipher.encrypt(plaintext.inputStream(), plaintext.size.toLong(), encrypted)
    val header = result.header
    val first = readRange(encrypted, header.segmentOffset(0), header.segmentEncryptedLength(0))
    SegmentedCipher.decryptSegment(result.dek, header, 1, first)
  }

  @Test(expected = IllegalArgumentException::class)
  fun rejectsTruncatedFiles() {
    val encrypted = folder.newFile()
    val result = SegmentedCipher.encrypt(VaultCrypto.randomBytes(segment + 10).inputStream(), segment + 10L, encrypted)
    RandomAccessFile(encrypted, "rw").use { it.setLength(encrypted.length() - 5) }
    SegmentedCipher.decrypt(result.dek, encrypted, ByteArrayOutputStream())
  }

  @Test(expected = IllegalArgumentException::class)
  fun rejectsUnknownHeaders() {
    SegmentedCipher.Header.parse(ByteArray(SegmentedCipher.HEADER_SIZE))
  }

  private fun readRange(file: File, offset: Long, length: Int): ByteArray =
    ByteArray(length).also { buffer ->
      RandomAccessFile(file, "r").use {
        it.seek(offset)
        it.readFully(buffer)
      }
    }

  private fun sha1(bytes: ByteArray): String = MessageDigest.getInstance("SHA-1").digest(bytes).toHex()
}
