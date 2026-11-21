package app.alextran.immich.keepsake

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.crypto.AEADBadTagException

private val keepsakeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

private fun <T> respond(callback: (Result<T>) -> Unit, block: suspend () -> T) {
  keepsakeScope.launch {
    val result = try {
      Result.success(block())
    } catch (error: Throwable) {
      Result.failure(error.toFlutterError())
    }
    withContext(Dispatchers.Main) { callback(result) }
  }
}

private fun Throwable.toFlutterError(): FlutterError = when (this) {
  is FlutterError -> this
  is VaultLockedException -> FlutterError("VAULT_LOCKED", message)
  is AEADBadTagException -> FlutterError("WRONG_SECRET", "The passphrase or recovery words are not correct")
  is TdException -> FlutterError("TELEGRAM_$code", message)
  is TimeoutCancellationException -> FlutterError("TIMEOUT", "Telegram did not respond in time")
  is TooLargeException -> FlutterError("TOO_LARGE", message)
  is java.io.IOException -> FlutterError("IO_ERROR", message ?: javaClass.simpleName)
  else -> FlutterError("KEEPSAKE_ERROR", message ?: javaClass.simpleName)
}

class KeepsakeTelegramApiImpl(private val services: KeepsakeServices) : KeepsakeTelegramApi {
  private val client get() = services.telegram

  override fun getAuthStatus(callback: (Result<TelegramAuthStatus>) -> Unit) = respond(callback) {
    client.start()
    status(client.awaitSettled())
  }

  override fun submitPhoneNumber(phoneNumber: String, callback: (Result<TelegramAuthStatus>) -> Unit) = respond(callback) {
    advance { client.submitPhoneNumber(phoneNumber.trim()) }
  }

  override fun submitCode(code: String, callback: (Result<TelegramAuthStatus>) -> Unit) = respond(callback) {
    advance { client.submitCode(code.trim()) }
  }

  override fun submitPassword(password: String, callback: (Result<TelegramAuthStatus>) -> Unit) = respond(callback) {
    advance { client.submitPassword(password) }
  }

  override fun ensureVaultChannels(vaultName: String, callback: (Result<VaultChannels>) -> Unit) = respond(callback) {
    requireReady()
    val state = services.channels.ensureChannels(vaultName)
    runCatching { services.library.publishVault(vaultName) }
    VaultChannels(state.libraryChatId, state.systemChatId)
  }

  override fun getVaultChannels(callback: (Result<VaultChannels?>) -> Unit) = respond(callback) {
    services.channels.channels()?.let { VaultChannels(it.libraryChatId, it.systemChatId) }
  }

  override fun runSelfTest(callback: (Result<SelfTestReport>) -> Unit) = respond(callback) {
    val steps = mutableListOf<String>()
    try {
      requireReady()
      services.channels.runSelfTest(steps)
      SelfTestReport(success = true, steps = steps)
    } catch (error: Throwable) {
      steps += "✗ ${error.toFlutterError().message}"
      SelfTestReport(success = false, steps = steps)
    }
  }

  override fun logOut(callback: (Result<Unit>) -> Unit) = respond(callback) {
    client.start()
    if (client.awaitSettled().step == TdAuthStep.READY) {
      client.logOut()
      client.awaitStateAfter(TdAuthStep.READY)
    }
  }

  private suspend fun advance(action: suspend () -> Unit): TelegramAuthStatus {
    client.start()
    val before = client.awaitSettled().step
    action()
    return status(client.awaitStateAfter(before))
  }

  private suspend fun requireReady() = services.requireTelegramReady()

  private suspend fun status(state: TdAuthState): TelegramAuthStatus = TelegramAuthStatus(
    step = when (state.step) {
      TdAuthStep.STARTING -> TelegramAuthStep.STARTING
      TdAuthStep.WAIT_PHONE_NUMBER -> TelegramAuthStep.WAIT_PHONE_NUMBER
      TdAuthStep.WAIT_CODE -> TelegramAuthStep.WAIT_CODE
      TdAuthStep.WAIT_PASSWORD -> TelegramAuthStep.WAIT_PASSWORD
      TdAuthStep.READY -> TelegramAuthStep.READY
      TdAuthStep.LOGGING_OUT -> TelegramAuthStep.LOGGING_OUT
      TdAuthStep.CLOSED -> TelegramAuthStep.CLOSED
    },
    passwordHint = state.passwordHint,
    accountName = if (state.step == TdAuthStep.READY) runCatching { client.accountName() }.getOrNull() else null,
  )
}

class KeepsakeVaultApiImpl(private val services: KeepsakeServices) : KeepsakeVaultApi {
  private val vault get() = services.vault

  override fun getStatus(callback: (Result<VaultStatus>) -> Unit) = respond(callback) {
    vault.restoreFromDevice()
    status()
  }

  override fun createVault(passphrase: String, recoveryEntropy: ByteArray, callback: (Result<VaultStatus>) -> Unit) =
    respond(callback) {
      vault.create(passphrase, recoveryEntropy)
      status()
    }

  override fun unlockWithPassphrase(passphrase: String, callback: (Result<VaultStatus>) -> Unit) = respond(callback) {
    vault.unlockWithPassphrase(passphrase)
    status()
  }

  override fun unlockWithRecoveryEntropy(recoveryEntropy: ByteArray, callback: (Result<VaultStatus>) -> Unit) =
    respond(callback) {
      vault.unlockWithRecoveryEntropy(recoveryEntropy)
      status()
    }

  override fun lock(callback: (Result<Unit>) -> Unit) = respond(callback) { vault.lock() }

  private fun status() = VaultStatus(exists = vault.exists, unlocked = vault.isUnlocked, vaultId = vault.vaultId())
}

class KeepsakeLibraryApiImpl(private val services: KeepsakeServices) : KeepsakeLibraryApi {
  private val library get() = services.library
  private val index get() = services.index

  override fun startMediaServer(callback: (Result<String>) -> Unit) = respond(callback) { services.mediaServer.start() }

  override fun changesSince(sinceSeq: Long, limit: Long, callback: (Result<LibraryChanges>) -> Unit) = respond(callback) {
    val changes = index.changesSince(sinceSeq, limit.toInt().coerceIn(1, MAX_PAGE))
    LibraryChanges(changes.records.map { it.toLibraryAsset() }, changes.deletedIds, changes.nextSeq, changes.hasMore)
  }

  override fun backupLocalAsset(request: BackupAssetRequest, callback: (Result<LibraryAsset>) -> Unit) = respond(callback) {
    services.requireTelegramReady()
    library.backup(
      BackupHints(
        localId = request.localId,
        checksum = request.checksum,
        createdAtMs = request.createdAtMs,
        modifiedAtMs = request.modifiedAtMs,
        isFavorite = request.isFavorite,
      )
    ).toLibraryAsset()
  }

  override fun trash(ids: List<String>, callback: (Result<Long>) -> Unit) = respond(callback) { library.trash(ids).toLong() }

  override fun restoreFromTrash(ids: List<String>, callback: (Result<Long>) -> Unit) = respond(callback) {
    library.restore(ids).toLong()
  }

  override fun restoreAllTrash(callback: (Result<Long>) -> Unit) = respond(callback) { library.restoreAllTrash().toLong() }

  override fun deletePermanently(ids: List<String>, callback: (Result<Long>) -> Unit) = respond(callback) {
    services.requireTelegramReady()
    library.deletePermanently(ids).toLong()
  }

  override fun emptyTrash(callback: (Result<Long>) -> Unit) = respond(callback) {
    services.requireTelegramReady()
    library.emptyTrash().toLong()
  }

  override fun updateAssets(update: LibraryAssetUpdate, callback: (Result<Long>) -> Unit) = respond(callback) {
    library.update(
      AssetUpdate(
        ids = update.ids,
        isFavorite = update.isFavorite,
        visibility = update.visibility?.toInt(),
        createdAtMs = update.createdAtMs,
        latitude = update.latitude,
        longitude = update.longitude,
      )
    ).toLong()
  }

  override fun updateDescription(id: String, description: String, callback: (Result<Long>) -> Unit) = respond(callback) {
    library.updateDescription(id, description).toLong()
  }

  override fun updateRating(id: String, rating: Long?, callback: (Result<Long>) -> Unit) = respond(callback) {
    library.updateRating(id, rating?.toInt()).toLong()
  }

  override fun getAsset(id: String, callback: (Result<LibraryAsset?>) -> Unit) = respond(callback) {
    index.find(id)?.toLibraryAsset()
  }

  override fun assetCount(callback: (Result<Long>) -> Unit) = respond(callback) { index.count() }

  override fun snapshotIndex(force: Boolean, callback: (Result<Long>) -> Unit) = respond(callback) {
    services.requireTelegramReady()
    library.snapshotIfDue(force)
  }

  override fun discoverAndAdoptVault(callback: (Result<DiscoveredVault?>) -> Unit) = respond(callback) {
    services.requireTelegramReady()
    library.discoverVault()?.let { discovery ->
      if (!services.vault.exists) library.adopt(discovery)
      DiscoveredVault(discovery.vaultName, discovery.libraryChatId, discovery.systemChatId)
    }
  }

  override fun restoreIndex(callback: (Result<Long>) -> Unit) = respond(callback) {
    services.requireTelegramReady()
    library.restoreIndex()
  }

  override fun getEncryptUploads(callback: (Result<Boolean>) -> Unit) = respond(callback) { library.encryptUploads() }

  override fun setEncryptUploads(enabled: Boolean, callback: (Result<Unit>) -> Unit) = respond(callback) {
    library.setEncryptUploads(enabled)
  }

  override fun createAlbum(name: String, description: String?, assetIds: List<String>, callback: (Result<LibraryAlbum>) -> Unit) =
    respond(callback) { index.createAlbum(name, description, assetIds).toLibraryAlbum() }

  override fun updateAlbum(
    id: String,
    name: String?,
    description: String?,
    thumbnailAssetId: String?,
    order: Long?,
    callback: (Result<LibraryAlbum?>) -> Unit,
  ) = respond(callback) { index.updateAlbum(id, name, description, thumbnailAssetId, order?.toInt())?.toLibraryAlbum() }

  override fun deleteAlbum(id: String, callback: (Result<Boolean>) -> Unit) = respond(callback) { index.deleteAlbum(id) }

  override fun addAlbumAssets(albumId: String, assetIds: List<String>, callback: (Result<List<String>>) -> Unit) =
    respond(callback) { index.addAlbumAssets(albumId, assetIds) }

  override fun removeAlbumAssets(albumId: String, assetIds: List<String>, callback: (Result<List<String>>) -> Unit) =
    respond(callback) { index.removeAlbumAssets(albumId, assetIds) }

  override fun albumChangesSince(sinceSeq: Long, untilSeq: Long, callback: (Result<AlbumChanges>) -> Unit) = respond(callback) {
    val changes = index.albumChangesSince(sinceSeq, untilSeq)
    AlbumChanges(
      albums = changes.albums.map { it.toLibraryAlbum() },
      deletedAlbumIds = changes.deletedAlbumIds,
      addedLinks = changes.addedLinks.map { AlbumAssetLink(it.albumId, it.assetId) },
      removedLinks = changes.removedLinks.map { AlbumAssetLink(it.albumId, it.assetId) },
      nextSeq = changes.nextSeq,
    )
  }

  private fun AlbumRecord.toLibraryAlbum() = LibraryAlbum(
    id = id,
    name = name,
    description = description,
    thumbnailAssetId = thumbnailAssetId,
    order = order.toLong(),
    createdAtMs = createdAtMs,
    updatedAtMs = updatedAtMs,
    assetCount = assetCount,
  )

  private fun IndexRecord.toLibraryAsset() = LibraryAsset(
    id = id,
    checksum = checksum,
    localId = localId,
    name = name,
    mimeType = mimeType,
    type = type.toLong(),
    createdAtMs = createdAtMs,
    modifiedAtMs = modifiedAtMs,
    width = width?.toLong(),
    height = height?.toLong(),
    durationMs = durationMs,
    sizeBytes = sizeBytes,
    latitude = latitude,
    longitude = longitude,
    make = make,
    model = model,
    orientation = orientation?.toLong(),
    isFavorite = isFavorite,
    visibility = visibility.toLong(),
    deletedAtMs = deletedAtMs,
    uploadedAtMs = uploadedAtMs,
    description = description,
    rating = rating?.toLong(),
  )

  private companion object {
    const val MAX_PAGE = 2000
  }
}
