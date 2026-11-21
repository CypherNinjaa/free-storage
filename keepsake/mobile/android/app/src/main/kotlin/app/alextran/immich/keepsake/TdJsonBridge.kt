package app.alextran.immich.keepsake

object TdJsonBridge {
  @Volatile
  private var loaded = false

  fun ensureLoaded() {
    if (loaded) return
    synchronized(this) {
      if (loaded) return
      System.loadLibrary("tdjson")
      System.loadLibrary("keepsake_tdbridge")
      loaded = true
    }
  }

  external fun nativeCreateClientId(): Int

  external fun nativeSend(clientId: Int, request: ByteArray)

  external fun nativeReceive(timeoutSeconds: Double): ByteArray?

  external fun nativeExecute(request: ByteArray): ByteArray?
}
