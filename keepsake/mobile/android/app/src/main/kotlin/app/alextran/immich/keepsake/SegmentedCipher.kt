package app.alextran.immich.keepsake

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

object SegmentedCipher {
  const val HEADER_SIZE = 64
  const val SEGMENT_SIZE = 1024 * 1024
  const val TAG_BYTES = 16
  private const val NONCE_BYTES = 12
  private const val VERSION = 1
  private val MAGIC = "IMTG".toByteArray(Charsets.US_ASCII)

  class Header(val segmentSize: Int, val plaintextSize: Long, val baseNonce: ByteArray) {
    val bytes: ByteArray = ByteBuffer.allocate(HEADER_SIZE).order(ByteOrder.BIG_ENDIAN).apply {
      put(MAGIC)
      putShort(VERSION.toShort())
      putInt(segmentSize)
      putLong(plaintextSize)
      put(baseNonce)
    }.array()

    val segmentCount: Long
      get() = if (plaintextSize == 0L) 0L else (plaintextSize + segmentSize - 1) / segmentSize

    val encryptedSize: Long
      get() = HEADER_SIZE + plaintextSize + segmentCount * TAG_BYTES

    fun segmentOffset(index: Long): Long = HEADER_SIZE + index * (segmentSize + TAG_BYTES).toLong()

    fun segmentPlaintextLength(index: Long): Int =
      minOf(segmentSize.toLong(), plaintextSize - index * segmentSize).toInt()

    fun segmentEncryptedLength(index: Long): Int = segmentPlaintextLength(index) + TAG_BYTES

    companion object {
      fun parse(bytes: ByteArray): Header {
        require(bytes.size >= HEADER_SIZE) { "Header is too short" }
        require(bytes.copyOfRange(0, MAGIC.size).contentEquals(MAGIC)) { "Not an Ambry encrypted file" }
        val buffer = ByteBuffer.wrap(bytes, MAGIC.size, HEADER_SIZE - MAGIC.size).order(ByteOrder.BIG_ENDIAN)
        val version = buffer.short.toInt()
        require(version == VERSION) { "Unsupported encrypted file version $version" }
        val segmentSize = buffer.int
        require(segmentSize > 0) { "Invalid segment size" }
        val plaintextSize = buffer.long
        require(plaintextSize >= 0) { "Invalid plaintext size" }
        val nonce = ByteArray(NONCE_BYTES).also(buffer::get)
        return Header(segmentSize, plaintextSize, nonce)
      }
    }
  }

  class EncryptionResult(val header: Header, val dek: ByteArray, val plaintextSha1: String)

  fun encrypt(input: InputStream, plaintextSize: Long, destination: File): EncryptionResult {
    val dek = VaultCrypto.randomBytes(VaultCrypto.KEY_BYTES)
    val header = Header(SEGMENT_SIZE, plaintextSize, VaultCrypto.randomBytes(NONCE_BYTES))
    val sha1 = MessageDigest.getInstance("SHA-1")
    destination.outputStream().buffered(256 * 1024).use { output ->
      output.write(header.bytes)
      val buffer = ByteArray(SEGMENT_SIZE)
      var index = 0L
      var total = 0L
      while (true) {
        val read = readFully(input, buffer)
        if (read == 0) break
        sha1.update(buffer, 0, read)
        output.write(cipher(Cipher.ENCRYPT_MODE, dek, header, index).doFinal(buffer, 0, read))
        total += read
        index++
      }
      require(total == plaintextSize) { "Expected $plaintextSize bytes but read $total" }
    }
    return EncryptionResult(header, dek, sha1.digest().toHex())
  }

  fun decryptSegment(dek: ByteArray, header: Header, index: Long, ciphertext: ByteArray): ByteArray {
    require(index in 0 until header.segmentCount) { "Segment $index is out of range" }
    require(ciphertext.size == header.segmentEncryptedLength(index)) { "Segment $index has the wrong length" }
    return cipher(Cipher.DECRYPT_MODE, dek, header, index).doFinal(ciphertext)
  }

  fun decrypt(dek: ByteArray, encrypted: File, output: OutputStream): String {
    val sha1 = MessageDigest.getInstance("SHA-1")
    encrypted.inputStream().buffered(256 * 1024).use { input ->
      val headerBytes = ByteArray(HEADER_SIZE)
      require(readFully(input, headerBytes) == HEADER_SIZE) { "Encrypted file is truncated" }
      val header = Header.parse(headerBytes)
      for (index in 0 until header.segmentCount) {
        val ciphertext = ByteArray(header.segmentEncryptedLength(index))
        require(readFully(input, ciphertext) == ciphertext.size) { "Encrypted file is truncated" }
        val plaintext = decryptSegment(dek, header, index, ciphertext)
        sha1.update(plaintext)
        output.write(plaintext)
      }
      require(input.read() == -1) { "Encrypted file has trailing data" }
    }
    return sha1.digest().toHex()
  }

  private fun cipher(mode: Int, dek: ByteArray, header: Header, index: Long): Cipher {
    val nonce = header.baseNonce.copyOf()
    val counter = ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN).putLong(index).array()
    for (i in counter.indices) {
      nonce[4 + i] = (nonce[4 + i].toInt() xor counter[i].toInt()).toByte()
    }
    val aad = ByteBuffer.allocate(HEADER_SIZE + 8).order(ByteOrder.BIG_ENDIAN).put(header.bytes).putLong(index).array()
    return Cipher.getInstance("AES/GCM/NoPadding").apply {
      init(mode, SecretKeySpec(dek, "AES"), GCMParameterSpec(TAG_BYTES * 8, nonce))
      updateAAD(aad)
    }
  }

  private fun readFully(input: InputStream, buffer: ByteArray): Int {
    var offset = 0
    while (offset < buffer.size) {
      val read = input.read(buffer, offset, buffer.size - offset)
      if (read < 0) break
      offset += read
    }
    return offset
  }
}

fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
