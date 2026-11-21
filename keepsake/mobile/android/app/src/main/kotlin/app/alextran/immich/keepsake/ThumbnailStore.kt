package app.alextran.immich.keepsake

import java.io.File

class ThumbnailStore(private val directory: File, private val vault: VaultStore) {
  enum class Kind(val suffix: String) { THUMBNAIL("t"), PREVIEW("p") }

  fun put(assetId: String, kind: Kind, jpeg: ByteArray) {
    val target = file(assetId, kind)
    target.parentFile?.mkdirs()
    val temp = File(target.parentFile, "${target.name}.tmp")
    temp.writeBytes(VaultCrypto.seal(key(), jpeg, aad(assetId, kind)))
    if (!temp.renameTo(target)) {
      target.delete()
      temp.renameTo(target)
    }
  }

  fun get(assetId: String, kind: Kind): ByteArray? {
    val source = file(assetId, kind)
    if (!source.exists()) return null
    return runCatching { VaultCrypto.open(key(), source.readBytes(), aad(assetId, kind)) }.getOrElse {
      source.delete()
      null
    }
  }

  fun delete(assetId: String) {
    Kind.entries.forEach { file(assetId, it).delete() }
  }

  private fun key(): ByteArray = VaultCrypto.subkey(vault.requireKey(), "thumbnail")

  private fun aad(assetId: String, kind: Kind) = "$assetId|${kind.suffix}".toByteArray()

  private fun file(assetId: String, kind: Kind) = File(File(directory, assetId.take(2)), "$assetId.${kind.suffix}")
}
