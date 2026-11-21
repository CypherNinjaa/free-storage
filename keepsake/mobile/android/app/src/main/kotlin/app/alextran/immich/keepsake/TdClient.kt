package app.alextran.immich.keepsake

import android.content.Context
import android.os.Build
import android.util.Log
import app.alextran.immich.BuildConfig
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

enum class TdAuthStep { STARTING, WAIT_PHONE_NUMBER, WAIT_CODE, WAIT_PASSWORD, READY, LOGGING_OUT, CLOSED }

data class TdAuthState(val step: TdAuthStep, val passwordHint: String? = null)

class TdException(val code: Int, override val message: String) : Exception(message)

data class UploadedDocument(
  val chatId: Long,
  val messageId: Long,
  val fileId: Int,
  val fileUniqueId: String,
  val fileSize: Long,
)

data class DocumentThumbnail(val path: String, val width: Int, val height: Int)

class TdClient(private val context: Context, private val deviceKeyWrapper: DeviceKeyWrapper) {
  private val requestCounter = AtomicLong(1)
  private val pendingRequests = ConcurrentHashMap<String, CompletableDeferred<JSONObject>>()
  private val pendingSends = ConcurrentHashMap<Long, CompletableDeferred<JSONObject>>()
  private val earlySendResults = ConcurrentHashMap<Long, JSONObject>()
  private val authState = MutableStateFlow(TdAuthState(TdAuthStep.STARTING))
  private val rootDir = File(context.filesDir, "keepsake/tdlib")

  @Volatile
  private var clientId = -1
  private val downloadLocks = ConcurrentHashMap<Int, Mutex>()

  @Volatile
  private var receiving = false

  val auth: StateFlow<TdAuthState> = authState.asStateFlow()

  @Synchronized
  fun start() {
    if (clientId >= 0) return
    check(BuildConfig.KEEPSAKE_TELEGRAM_API_ID != 0 && BuildConfig.KEEPSAKE_TELEGRAM_API_HASH.isNotBlank()) {
      "Telegram api_id/api_hash are missing from the build (.env)"
    }
    TdJsonBridge.ensureLoaded()
    TdJsonBridge.nativeExecute(JSONObject().put("@type", "setLogVerbosityLevel").put("new_verbosity_level", 1).bytes())
    authState.value = TdAuthState(TdAuthStep.STARTING)
    clientId = TdJsonBridge.nativeCreateClientId()
    check(clientId >= 0) { "TDLib could not be loaded" }
    if (!receiving) {
      receiving = true
      Thread(::receiveLoop, "keepsake-tdlib").apply { isDaemon = true }.start()
    }
    TdJsonBridge.nativeSend(clientId, JSONObject().put("@type", "getOption").put("name", "version").bytes())
  }

  suspend fun awaitStateAfter(previous: TdAuthStep, timeoutMs: Long = 60_000): TdAuthState =
    withTimeout(timeoutMs) { authState.first { it.step != previous && it.step != TdAuthStep.STARTING } }

  suspend fun awaitSettled(timeoutMs: Long = 30_000): TdAuthState =
    withTimeout(timeoutMs) { authState.first { it.step != TdAuthStep.STARTING } }

  suspend fun send(request: JSONObject, timeoutMs: Long = 60_000): JSONObject {
    val id = "k${requestCounter.getAndIncrement()}"
    request.put("@extra", id)
    val deferred = CompletableDeferred<JSONObject>()
    pendingRequests[id] = deferred
    TdJsonBridge.nativeSend(clientId, request.bytes())
    val response = try {
      withTimeout(timeoutMs) { deferred.await() }
    } finally {
      pendingRequests.remove(id)
    }
    if (response.optString("@type") == "error") {
      throw TdException(response.optInt("code"), response.optString("message"))
    }
    return response
  }

  suspend fun submitPhoneNumber(phoneNumber: String) {
    send(JSONObject().put("@type", "setAuthenticationPhoneNumber").put("phone_number", phoneNumber))
  }

  suspend fun submitCode(code: String) {
    send(JSONObject().put("@type", "checkAuthenticationCode").put("code", code))
  }

  suspend fun submitPassword(password: String) {
    send(JSONObject().put("@type", "checkAuthenticationPassword").put("password", password))
  }

  suspend fun logOut() {
    send(JSONObject().put("@type", "logOut"))
  }

  suspend fun accountName(): String {
    val me = send(JSONObject().put("@type", "getMe"))
    return listOf(me.optString("first_name"), me.optString("last_name")).filter { it.isNotBlank() }.joinToString(" ")
  }

  suspend fun chatExists(chatId: Long): Boolean = try {
    send(JSONObject().put("@type", "getChat").put("chat_id", chatId))
    true
  } catch (error: TdException) {
    if (error.code == 400) false else throw error
  }

  suspend fun createPrivateChannel(title: String, description: String): Long =
    send(
      JSONObject()
        .put("@type", "createNewSupergroupChat")
        .put("title", title)
        .put("is_forum", false)
        .put("is_channel", true)
        .put("description", description)
    ).getLong("id")

  /**
   * Sends [path] as a file (never re-encoded as a photo or video). [thumbnail] is an optional JPEG of at most
   * 320x320 px and 200 kB that Telegram apps show next to the file.
   */
  suspend fun sendDocument(
    chatId: Long,
    path: String,
    caption: String,
    timeoutMs: Long = 3_600_000,
    thumbnail: DocumentThumbnail? = null,
  ): UploadedDocument {
    val document = JSONObject()
      .put("@type", "inputDocument")
      .put("document", JSONObject().put("@type", "inputFileLocal").put("path", path))
      .put("disable_content_type_detection", true)
    if (thumbnail != null) {
      document.put(
        "thumbnail",
        JSONObject()
          .put("@type", "inputThumbnail")
          .put("thumbnail", JSONObject().put("@type", "inputFileLocal").put("path", thumbnail.path))
          .put("width", thumbnail.width)
          .put("height", thumbnail.height),
      )
    }
    val pending = send(
      JSONObject()
        .put("@type", "sendMessage")
        .put("chat_id", chatId)
        .put(
          "input_message_content",
          JSONObject()
            .put("@type", "inputMessageDocument")
            .put("document", document)
            .put("caption", JSONObject().put("@type", "formattedText").put("text", caption))
        )
    )
    val message = if (pending.optJSONObject("sending_state") == null) pending else awaitSendResult(pending.getLong("id"), timeoutMs)
    val stored = message.getJSONObject("content").getJSONObject("document").getJSONObject("document")
    return UploadedDocument(
      chatId = chatId,
      messageId = message.getLong("id"),
      fileId = stored.getInt("id"),
      fileUniqueId = stored.getJSONObject("remote").optString("unique_id"),
      fileSize = stored.optLong("size"),
    )
  }

  suspend fun getMessages(chatId: Long, messageIds: List<Long>): List<JSONObject?> {
    val response = send(JSONObject().put("@type", "getMessages").put("chat_id", chatId).put("message_ids", JSONArray(messageIds)))
    val messages = response.getJSONArray("messages")
    return List(messages.length()) { index -> messages.optJSONObject(index) }
  }

  suspend fun searchMessageIds(chatId: Long, query: String, limit: Int = 20): List<Long> {
    val response = send(
      JSONObject()
        .put("@type", "searchChatMessages")
        .put("chat_id", chatId)
        .put("query", query)
        .put("from_message_id", 0)
        .put("offset", 0)
        .put("limit", limit)
    )
    val messages = response.getJSONArray("messages")
    return List(messages.length()) { index -> messages.getJSONObject(index).getLong("id") }
  }

  suspend fun deleteMessages(chatId: Long, messageIds: List<Long>) {
    send(JSONObject().put("@type", "deleteMessages").put("chat_id", chatId).put("message_ids", JSONArray(messageIds)).put("revoke", true))
  }

  /**
   * Returns bytes [offset, offset + length) of a Telegram file.
   *
   * A synchronous downloadFile returns early when another downloadFile with a different range is sent for the
   * same file (video players read several ranges at once), so ranges of one file are fetched one at a time and
   * TDLib is asked whether the range is really present before it is read from disk.
   */
  suspend fun downloadRange(fileId: Int, offset: Long, length: Int): ByteArray =
    downloadLocks.getOrPut(fileId) { Mutex() }.withLock {
      repeat(DOWNLOAD_ATTEMPTS) {
        val file = send(
          JSONObject()
            .put("@type", "downloadFile")
            .put("file_id", fileId)
            .put("priority", 32)
            .put("offset", offset)
            .put("limit", length)
            .put("synchronous", true),
          timeoutMs = 300_000,
        )
        val local = file.getJSONObject("local")
        val path = local.optString("path")
        when {
          path.isNotBlank() && rangeAvailable(fileId, local, path, offset, length) -> {
            return@withLock ByteArray(length).also { buffer ->
              RandomAccessFile(path, "r").use { raf ->
                raf.seek(offset)
                raf.readFully(buffer)
              }
            }
          }
          local.optBoolean("is_downloading_completed") -> {
            // TDLib still points at a local copy that is gone (for example the temporary file an upload was made
            // from). Forget it so the next attempt downloads from Telegram.
            runCatching { send(JSONObject().put("@type", "deleteFile").put("file_id", fileId)) }
          }
        }
      }
      throw IOException("Telegram did not deliver bytes $offset..${offset + length} of file $fileId")
    }

  private suspend fun rangeAvailable(fileId: Int, local: JSONObject, path: String, offset: Long, length: Int): Boolean {
    if (local.optBoolean("is_downloading_completed")) return File(path).length() >= offset + length
    val prefix = send(
      JSONObject().put("@type", "getFileDownloadedPrefixSize").put("file_id", fileId).put("offset", offset)
    )
    return prefix.optLong("size", prefix.optLong("count", 0)) >= length
  }

  suspend fun sendText(chatId: Long, text: String): Long {
    val pending = send(
      JSONObject()
        .put("@type", "sendMessage")
        .put("chat_id", chatId)
        .put(
          "input_message_content",
          JSONObject()
            .put("@type", "inputMessageText")
            .put("text", JSONObject().put("@type", "formattedText").put("text", text))
        )
    )
    val message = if (pending.optJSONObject("sending_state") == null) pending else awaitSendResult(pending.getLong("id"), 120_000)
    return message.getLong("id")
  }

  suspend fun pinMessage(chatId: Long, messageId: Long) {
    send(
      JSONObject()
        .put("@type", "pinChatMessage")
        .put("chat_id", chatId)
        .put("message_id", messageId)
        .put("disable_notification", true)
        .put("only_for_self", false)
    )
  }

  suspend fun loadChats(limit: Int = 200) {
    try {
      send(JSONObject().put("@type", "loadChats").put("chat_list", JSONObject().put("@type", "chatListMain")).put("limit", limit))
    } catch (error: TdException) {
      if (error.code != 404) throw error
    }
  }

  suspend fun searchChatIds(query: String, limit: Int = 50): List<Long> {
    val ids = LinkedHashSet<Long>()
    for (method in listOf("searchChats", "searchChatsOnServer")) {
      runCatching {
        val response = send(JSONObject().put("@type", method).put("query", query).put("limit", limit))
        val chatIds = response.getJSONArray("chat_ids")
        for (index in 0 until chatIds.length()) ids += chatIds.getLong(index)
      }
    }
    return ids.toList()
  }

  suspend fun chat(chatId: Long): JSONObject = send(JSONObject().put("@type", "getChat").put("chat_id", chatId))

  suspend fun history(chatId: Long, fromMessageId: Long, limit: Int = 100): List<JSONObject> {
    val response = send(
      JSONObject()
        .put("@type", "getChatHistory")
        .put("chat_id", chatId)
        .put("from_message_id", fromMessageId)
        .put("offset", 0)
        .put("limit", limit)
        .put("only_local", false)
    )
    val messages = response.getJSONArray("messages")
    return List(messages.length()) { index -> messages.getJSONObject(index) }
  }

  suspend fun searchMessages(chatId: Long, query: String, limit: Int = 50): List<JSONObject> {
    val response = send(
      JSONObject()
        .put("@type", "searchChatMessages")
        .put("chat_id", chatId)
        .put("query", query)
        .put("from_message_id", 0)
        .put("offset", 0)
        .put("limit", limit)
    )
    val messages = response.getJSONArray("messages")
    return List(messages.length()) { index -> messages.getJSONObject(index) }
  }

  suspend fun downloadWhole(fileId: Int, timeoutMs: Long = 3_600_000): String {
    val file = send(
      JSONObject()
        .put("@type", "downloadFile")
        .put("file_id", fileId)
        .put("priority", 16)
        .put("offset", 0)
        .put("limit", 0)
        .put("synchronous", true),
      timeoutMs = timeoutMs,
    )
    val local = file.getJSONObject("local")
    check(local.optBoolean("is_downloading_completed")) { "Download of file $fileId did not complete" }
    return local.getString("path")
  }

  suspend fun documentFileId(chatId: Long, messageId: Long): Int? {
    val message = getMessages(chatId, listOf(messageId)).singleOrNull() ?: return null
    return message.optJSONObject("content")?.optJSONObject("document")?.optJSONObject("document")?.optInt("id")
  }

  private suspend fun awaitSendResult(temporaryId: Long, timeoutMs: Long): JSONObject {
    val deferred = CompletableDeferred<JSONObject>()
    pendingSends[temporaryId] = deferred
    earlySendResults.remove(temporaryId)?.let { pendingSends.remove(temporaryId)?.complete(it) }
    val result = try {
      withTimeout(timeoutMs) { deferred.await() }
    } finally {
      pendingSends.remove(temporaryId)
    }
    if (result.optString("@type") == "updateMessageSendFailed") {
      val error = result.optJSONObject("error")
      throw TdException(error?.optInt("code") ?: 0, error?.optString("message") ?: "Upload failed")
    }
    return result.getJSONObject("message")
  }

  private fun receiveLoop() {
    while (true) {
      val raw = TdJsonBridge.nativeReceive(1.0) ?: continue
      try {
        handle(JSONObject(String(raw, Charsets.UTF_8)))
      } catch (error: Throwable) {
        Log.e(TAG, "Failed to handle TDLib response", error)
      }
    }
  }

  private fun handle(response: JSONObject) {
    val extra = response.optString("@extra")
    if (extra == PARAMETERS_EXTRA) {
      if (response.optString("@type") == "error") {
        Log.e(TAG, "setTdlibParameters failed: ${response.optString("message")}")
      }
      return
    }
    if (extra.isNotEmpty()) {
      pendingRequests[extra]?.let {
        it.complete(response)
        return
      }
    }
    when (response.optString("@type")) {
      "updateAuthorizationState" -> handleAuthorizationState(response.getJSONObject("authorization_state"))
      "updateMessageSendSucceeded", "updateMessageSendFailed" -> {
        val temporaryId = response.optLong("old_message_id", -1)
        pendingSends.remove(temporaryId)?.complete(response) ?: earlySendResults.put(temporaryId, response)
      }
    }
  }

  private fun handleAuthorizationState(state: JSONObject) {
    authState.value = when (state.optString("@type")) {
      "authorizationStateWaitTdlibParameters" -> {
        sendTdlibParameters()
        TdAuthState(TdAuthStep.STARTING)
      }
      "authorizationStateWaitPhoneNumber" -> TdAuthState(TdAuthStep.WAIT_PHONE_NUMBER)
      "authorizationStateWaitCode" -> TdAuthState(TdAuthStep.WAIT_CODE)
      "authorizationStateWaitPassword" -> TdAuthState(TdAuthStep.WAIT_PASSWORD, state.optString("password_hint").ifBlank { null })
      "authorizationStateReady" -> TdAuthState(TdAuthStep.READY)
      "authorizationStateLoggingOut" -> TdAuthState(TdAuthStep.LOGGING_OUT)
      "authorizationStateClosing" -> TdAuthState(TdAuthStep.LOGGING_OUT)
      "authorizationStateClosed" -> {
        clientId = -1
        TdAuthState(TdAuthStep.CLOSED)
      }
      else -> authState.value
    }
  }

  private fun sendTdlibParameters() {
    val parameters = JSONObject()
      .put("@type", "setTdlibParameters")
      .put("use_test_dc", false)
      .put("database_directory", File(rootDir, "db").apply { mkdirs() }.absolutePath)
      .put("files_directory", File(rootDir, "files").apply { mkdirs() }.absolutePath)
      .put("database_encryption_key", Base64.getEncoder().encodeToString(databaseKey()))
      .put("use_file_database", true)
      .put("use_chat_info_database", true)
      .put("use_message_database", true)
      .put("use_secret_chats", false)
      .put("api_id", BuildConfig.KEEPSAKE_TELEGRAM_API_ID)
      .put("api_hash", BuildConfig.KEEPSAKE_TELEGRAM_API_HASH)
      .put("system_language_code", "en")
      .put("device_model", Build.MODEL ?: "Android")
      .put("system_version", "Android ${Build.VERSION.RELEASE}")
      .put("application_version", BuildConfig.VERSION_NAME)
      .put("@extra", PARAMETERS_EXTRA)
    TdJsonBridge.nativeSend(clientId, parameters.bytes())
  }

  private fun databaseKey(): ByteArray {
    val keyFile = File(rootDir, "db-key.bin")
    if (keyFile.exists()) {
      runCatching { return deviceKeyWrapper.unwrap(keyFile.readBytes()) }
      File(rootDir, "db").deleteRecursively()
    }
    val key = VaultCrypto.randomBytes(VaultCrypto.KEY_BYTES)
    rootDir.mkdirs()
    keyFile.writeBytes(deviceKeyWrapper.wrap(key))
    return key
  }

  private fun JSONObject.bytes(): ByteArray = toString().toByteArray(Charsets.UTF_8)

  private companion object {
    const val TAG = "KeepsakeTdClient"
    const val DOWNLOAD_ATTEMPTS = 3
    const val PARAMETERS_EXTRA = "keepsake-tdlib-parameters"
  }
}
