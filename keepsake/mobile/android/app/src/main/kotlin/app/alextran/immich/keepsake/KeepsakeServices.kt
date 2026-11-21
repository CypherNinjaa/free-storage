package app.alextran.immich.keepsake

import android.content.Context
import java.io.File

class KeepsakeServices private constructor(context: Context) {
  private val root = File(context.filesDir, "keepsake")
  private val deviceKeyWrapper = AndroidKeystoreKeyWrapper("keepsake.device.v1")

  val vault = VaultStore(File(root, "vault"), deviceKeyWrapper)
  val telegram = TdClient(context, deviceKeyWrapper)
  val channels = TelegramVault(root, context.cacheDir, telegram, vault)
  val index = KeepsakeIndex(context, File(root, "index").apply { mkdirs() }.resolve("keepsake-index.db"))
  private val thumbnails = ThumbnailStore(File(root, "thumbs"), vault)
  private val reader = RemoteAssetReader(telegram, index, vault)
  val library = KeepsakeLibrary(context, telegram, vault, channels, index, thumbnails, reader, LocalMediaReader(context))
  val mediaServer = MediaServer(library, File(root, "media.json"))

  init {
    vault.restoreFromDevice()
    // Temporary files of uploads, snapshots or renders cut short by a killed process. This runs once per process,
    // before any Keepsake work starts, so none of them is in use.
    context.cacheDir.listFiles { file -> file.name.startsWith("keepsake-") }?.forEach { it.deleteRecursively() }
  }

  suspend fun requireTelegramReady() {
    telegram.start()
    if (telegram.awaitSettled().step != TdAuthStep.READY) {
      throw FlutterError("TELEGRAM_NOT_CONNECTED", "Connect the Telegram account first")
    }
  }

  companion object {
    @Volatile
    private var instance: KeepsakeServices? = null

    fun get(context: Context): KeepsakeServices =
      instance ?: synchronized(this) {
        instance ?: KeepsakeServices(context.applicationContext).also { instance = it }
      }
  }
}
