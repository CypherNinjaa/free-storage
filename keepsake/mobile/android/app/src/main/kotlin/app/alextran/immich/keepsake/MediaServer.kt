package app.alextran.immich.keepsake

import android.util.Log
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import java.security.MessageDigest
import java.util.concurrent.Executors

@Serializable
private data class MediaServerState(val token: String, val port: Int)

class MediaServer(private val library: KeepsakeLibrary, private val stateFile: File) {
  private val workers = Executors.newFixedThreadPool(WORKERS) { runnable ->
    Thread(runnable, "keepsake-media").apply { isDaemon = true }
  }
  private val json = Json { ignoreUnknownKeys = true }
  private var token = ""

  @Volatile
  private var endpoint: String? = null

  @Synchronized
  fun start(): String {
    endpoint?.let { return it }
    val state = loadState()
    val server = runCatching { ServerSocket(state.port, BACKLOG, LOOPBACK) }
      .getOrElse { ServerSocket(0, BACKLOG, LOOPBACK) }
    if (server.localPort != state.port) saveState(state.copy(port = server.localPort))
    token = state.token
    Thread({ accept(server) }, "keepsake-media-accept").apply { isDaemon = true }.start()
    return "http://127.0.0.1:${server.localPort}/${state.token}".also { endpoint = it }
  }

  private fun accept(server: ServerSocket) {
    while (!server.isClosed) {
      val client = runCatching { server.accept() }.getOrNull() ?: continue
      workers.execute { client.use(::handle) }
    }
  }

  private fun handle(client: Socket) {
    client.soTimeout = 60_000
    val input = BufferedInputStream(client.getInputStream())
    val output = BufferedOutputStream(client.getOutputStream(), 64 * 1024)
    try {
      val requestLine = readLine(input) ?: return
      val headers = HashMap<String, String>()
      while (true) {
        val line = readLine(input) ?: break
        if (line.isEmpty()) break
        val separator = line.indexOf(':')
        if (separator > 0) headers[line.substring(0, separator).trim().lowercase()] = line.substring(separator + 1).trim()
      }
      val parts = requestLine.split(' ')
      if (parts.size < 2) return
      route(parts[0], parts[1], headers, output)
    } catch (error: Throwable) {
      Log.w(TAG, "Media request failed: ${error.message}")
      runCatching { status(output, 500, "Internal Server Error") }
    } finally {
      runCatching { output.flush() }
    }
  }

  private fun route(method: String, target: String, headers: Map<String, String>, output: OutputStream) {
    val path = target.substringBefore('?')
    val query = target.substringAfter('?', "").split('&').filter { it.contains('=') }.associate {
      URLDecoder.decode(it.substringBefore('='), "UTF-8") to URLDecoder.decode(it.substringAfter('='), "UTF-8")
    }
    val segments = path.trim('/').split('/')
    if (segments.size < 4 || !MessageDigest.isEqual(segments[0].toByteArray(), token.toByteArray()) || segments[1] != "assets") {
      return status(output, 404, "Not Found")
    }
    val assetId = segments[2]
    val headOnly = method.equals("HEAD", ignoreCase = true)
    when (segments.drop(3).joinToString("/")) {
      "thumbnail" -> when (query["size"]) {
        "fullsize" -> stream(assetId, headers, output, headOnly, imagesOnly = true)
        "preview" -> image(assetId, ThumbnailStore.Kind.PREVIEW, output, headOnly)
        else -> image(assetId, ThumbnailStore.Kind.THUMBNAIL, output, headOnly)
      }
      "original", "video/playback" -> stream(assetId, headers, output, headOnly, imagesOnly = false)
      else -> status(output, 404, "Not Found")
    }
  }

  private fun image(assetId: String, kind: ThumbnailStore.Kind, output: OutputStream, headOnly: Boolean) {
    val bytes = runBlocking { library.image(assetId, kind) } ?: return status(output, 404, "Not Found")
    writeHead(
      output,
      200,
      "OK",
      mapOf(
        "Content-Type" to "image/jpeg",
        "Content-Length" to bytes.size.toString(),
        // The vault keeps its own encrypted thumbnail cache, so decrypted bytes must not be persisted by HTTP caches.
        "Cache-Control" to "no-store",
      ),
    )
    if (!headOnly) output.write(bytes)
  }

  private fun stream(assetId: String, headers: Map<String, String>, output: OutputStream, headOnly: Boolean, imagesOnly: Boolean) {
    val record = library.index.find(assetId) ?: return status(output, 404, "Not Found")
    if (imagesOnly && record.type == KeepsakeIndex.TYPE_VIDEO) {
      return image(assetId, ThumbnailStore.Kind.PREVIEW, output, headOnly)
    }
    val file = runBlocking { library.openRemote(record) }
    val size = file.size
    val requested = headers["range"]
    val range = requested?.let { parseRange(it, size) }
    if (requested != null && range == null) {
      writeHead(output, 416, "Range Not Satisfiable", mapOf("Content-Range" to "bytes */$size", "Content-Length" to "0"))
      return
    }
    val start = range?.first ?: 0L
    val end = range?.second ?: (size - 1)
    val length = if (size == 0L) 0L else end - start + 1
    val responseHeaders = linkedMapOf(
      "Content-Type" to record.mimeType,
      "Content-Length" to length.toString(),
      "Accept-Ranges" to "bytes",
      // The vault keeps its own encrypted thumbnail cache, so decrypted bytes must not be persisted by HTTP caches.
      "Cache-Control" to "no-store",
    )
    if (range != null) responseHeaders["Content-Range"] = "bytes $start-$end/$size"
    writeHead(output, if (range != null) 206 else 200, if (range != null) "Partial Content" else "OK", responseHeaders)
    if (!headOnly && length > 0) runBlocking { library.copyPlaintext(file, output, start, end) }
  }

  private fun parseRange(header: String, size: Long): Pair<Long, Long>? {
    if (size <= 0 || !header.startsWith("bytes=")) return null
    val spec = header.removePrefix("bytes=").substringBefore(',').trim()
    val startText = spec.substringBefore('-').trim()
    val endText = spec.substringAfter('-', "").trim()
    return when {
      startText.isEmpty() -> endText.toLongOrNull()?.takeIf { it > 0 }?.let { suffix -> maxOf(0, size - suffix) to size - 1 }
      else -> {
        val start = startText.toLongOrNull() ?: return null
        val end = endText.toLongOrNull()?.coerceAtMost(size - 1) ?: (size - 1)
        if (start >= size || end < start) null else start to end
      }
    }
  }

  private fun status(output: OutputStream, code: Int, reason: String) {
    writeHead(output, code, reason, mapOf("Content-Length" to "0"))
  }

  private fun writeHead(output: OutputStream, code: Int, reason: String, headers: Map<String, String>) {
    val head = buildString {
      append("HTTP/1.1 $code $reason\r\n")
      headers.forEach { (name, value) -> append("$name: $value\r\n") }
      append("Connection: close\r\n\r\n")
    }
    output.write(head.toByteArray(Charsets.US_ASCII))
  }

  private fun readLine(input: InputStream): String? {
    val line = StringBuilder()
    while (true) {
      val byte = input.read()
      if (byte == -1) return if (line.isEmpty()) null else line.toString()
      if (byte == '\n'.code) return line.toString().trimEnd('\r')
      if (line.length > MAX_LINE) return null
      line.append(byte.toChar())
    }
  }

  private fun loadState(): MediaServerState {
    val existing = runCatching { json.decodeFromString<MediaServerState>(stateFile.readText()) }.getOrNull()
    return existing ?: MediaServerState(VaultCrypto.randomBytes(24).toHex(), DEFAULT_PORT).also(::saveState)
  }

  private fun saveState(state: MediaServerState) {
    stateFile.parentFile?.mkdirs()
    stateFile.writeText(json.encodeToString(state))
  }

  private companion object {
    const val TAG = "KeepsakeMediaServer"
    const val DEFAULT_PORT = 47819
    const val BACKLOG = 64
    const val WORKERS = 8
    const val MAX_LINE = 8192
    val LOOPBACK: InetAddress = InetAddress.getByName("127.0.0.1")
  }
}
