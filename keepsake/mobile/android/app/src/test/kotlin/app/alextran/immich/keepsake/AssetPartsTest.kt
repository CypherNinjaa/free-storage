package app.alextran.immich.keepsake

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.security.MessageDigest

class AssetPartsTest {
  @get:Rule
  val folder = TemporaryFolder()

  private val segment = SegmentedCipher.SEGMENT_SIZE
  private val partBytes = 2L * segment

  @Test
  fun encryptedPartsAreTheWholeStreamCutAtSegmentBoundaries() {
    for (size in listOf(4 * segment + 1, 5 * segment + 123, 6 * segment)) {
      val plaintext = VaultCrypto.randomBytes(size)
      val dek = VaultCrypto.randomBytes(VaultCrypto.KEY_BYTES)
      val header = SegmentedCipher.newHeader(size.toLong())
      val wholeFile = folder.newFile()
      SegmentedCipher.encrypt(plaintext.inputStream(), size.toLong(), wholeFile, dek, header)
      val whole = wholeFile.readBytes()
      val layout = PartLayout(size.toLong(), partBytes, encrypted = true)

      assertEquals((size + partBytes - 1) / partBytes, layout.partCount.toLong())
      assertEquals(header.encryptedSize, layout.totalStoredSize)

      var start = 0
      for (part in 0 until layout.partCount) {
        val output = ByteArrayOutputStream()
        if (part == 0) output.write(header.bytes)
        val input = plaintext.inputStream().apply { skip(layout.plainStart(part)) }
        val read = SegmentedCipher.encryptSegments(input, dek, header, layout.firstSegment(part), layout.segmentCount(part), output)
        val bytes = output.toByteArray()

        assertEquals(layout.plainEnd(part) - layout.plainStart(part), read)
        assertEquals(layout.storedSize(part), bytes.size.toLong())
        assertArrayEquals(whole.copyOfRange(start, start + bytes.size), bytes)
        start += bytes.size
      }
      assertEquals(whole.size, start)
    }
  }

  @Test
  fun everySegmentIsReadFromOnePartAndDecrypts() {
    val size = 5 * segment + 77
    val plaintext = VaultCrypto.randomBytes(size)
    val dek = VaultCrypto.randomBytes(VaultCrypto.KEY_BYTES)
    val header = SegmentedCipher.newHeader(size.toLong())
    val layout = PartLayout(size.toLong(), partBytes, encrypted = true)
    val parts = (0 until layout.partCount).map { part ->
      ByteArrayOutputStream().also { output ->
        if (part == 0) output.write(header.bytes)
        SegmentedCipher.encryptSegments(
          plaintext.inputStream().apply { skip(layout.plainStart(part)) }, dek, header,
          layout.firstSegment(part), layout.segmentCount(part), output,
        )
      }.toByteArray()
    }

    assertEquals(0 to 0L, layout.locate(0))
    for (index in 0 until header.segmentCount) {
      val (part, offset) = layout.locate(header.segmentOffset(index))
      val length = header.segmentEncryptedLength(index)
      val ciphertext = parts[part].copyOfRange(offset.toInt(), offset.toInt() + length)
      val start = (index * segment).toInt()
      assertArrayEquals(
        plaintext.copyOfRange(start, minOf(size, start + segment)),
        SegmentedCipher.decryptSegment(dek, header, index, ciphertext),
      )
    }
  }

  @Test
  fun plainPartsAreByteRangesOfTheOriginal() {
    val size = 5L * segment + 7
    val layout = PartLayout(size, partBytes, encrypted = false)

    assertEquals(3, layout.partCount)
    assertEquals(partBytes, layout.storedSize(0))
    assertEquals(size - 2 * partBytes, layout.storedSize(2))
    assertEquals(size, layout.totalStoredSize)
    assertEquals(0 to 0L, layout.locate(0))
    assertEquals(1 to 0L, layout.locate(partBytes))
    assertEquals(1 to segment.toLong(), layout.locate(partBytes + segment))
    assertEquals(2 to segment + 6L, layout.locate(size - 1))
  }

  @Test
  fun sizesThatFillWholePartsAndEmptyFiles() {
    val exact = PartLayout(2 * partBytes, partBytes, encrypted = true)
    assertEquals(2, exact.partCount)
    assertEquals(SegmentedCipher.newHeader(2 * partBytes).encryptedSize, exact.totalStoredSize)
    assertEquals(1 to 0L, exact.locate(SegmentedCipher.HEADER_SIZE + exact.storedSize(1)))

    val empty = PartLayout(0, partBytes, encrypted = true)
    assertEquals(1, empty.partCount)
    assertEquals(SegmentedCipher.HEADER_SIZE.toLong(), empty.storedSize(0))
  }

  @Test(expected = IllegalArgumentException::class)
  fun rejectsPartSizesThatSplitASegment() {
    PartLayout(10L * segment, segment + 1L, encrypted = true)
  }

  @Test
  fun realPartSizesFitInOneTelegramFile() {
    val telegramLimit = 2000L * 1024 * 1024
    val fiveGiB = 5L * 1024 * 1024 * 1024
    val plain = PartLayout(fiveGiB, KeepsakeLibrary.PLAIN_PART_BYTES, encrypted = false)
    val encrypted = PartLayout(fiveGiB, KeepsakeLibrary.ENCRYPTED_PART_BYTES, encrypted = true)

    assertEquals(3, plain.partCount)
    assertEquals(20, encrypted.partCount)
    for (layout in listOf(plain, encrypted)) {
      for (part in 0 until layout.partCount) assertTrue(layout.storedSize(part) < telegramLimit)
    }
    assertTrue(KeepsakeLibrary.MAX_OBJECT_BYTES < telegramLimit)
    assertTrue(KeepsakeLibrary.SPLIT_ENCRYPTED_ABOVE_BYTES <= KeepsakeLibrary.MAX_OBJECT_BYTES)
  }

  @Test
  fun captionsCarryThePartAndOlderCaptionsDecodeAsSingleFiles() {
    val key = VaultCrypto.randomBytes(VaultCrypto.KEY_BYTES)
    val part = RecoveryRecord(
      assetId = "a1b2c3",
      sha1 = sha1(byteArrayOf(1, 2, 3)),
      takenAtEpochSec = 1_700_000_000,
      sizeBytes = 5L * 1024 * 1024 * 1024,
      mimeType = "video/mp4",
      fileName = "VID_20261127.mp4",
      dek = "a2V5",
      partIndex = 2,
      partCount = 20,
      partBytes = KeepsakeLibrary.ENCRYPTED_PART_BYTES,
    )
    assertEquals(part, VaultCaption.decode(key, VaultCaption.encode(key, part)))

    val single = part.copy(partIndex = 0, partCount = 1, partBytes = 0)
    val decoded = VaultCaption.decode(key, VaultCaption.encode(key, single))
    assertEquals(single, decoded)
    assertEquals(1, decoded?.partCount)
    assertTrue("Telegram captions hold at most 1024 characters", VaultCaption.encode(key, part).length < 1024)
  }

  private fun sha1(bytes: ByteArray): String = MessageDigest.getInstance("SHA-1").digest(bytes).toHex()
}
