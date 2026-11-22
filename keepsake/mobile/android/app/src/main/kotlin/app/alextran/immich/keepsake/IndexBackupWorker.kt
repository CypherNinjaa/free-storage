package app.alextran.immich.keepsake

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Backs up the library index once a day, independently of photo backup: whenever the index changed since the
 * last snapshot (new uploads, albums, favourites, trash, edits), an encrypted copy goes to the System channel.
 * The same run publishes the vault discovery record if it is missing and empties trash older than 30 days.
 */
class IndexBackupWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

  override suspend fun doWork(): Result {
    val services = KeepsakeServices.get(applicationContext)
    if (!services.vault.isUnlocked || services.channels.channels() == null) {
      Log.i(TAG, "No unlocked vault on this phone yet; nothing to back up")
      return Result.success()
    }
    return try {
      services.requireTelegramReady()
      val count = services.library.snapshotIfDue(force = false)
      Log.i(TAG, if (count >= 0) "Daily index backup stored ($count assets)" else "Daily index backup not due: the last one is recent or nothing changed")
      Result.success()
    } catch (error: VaultInUseException) {
      Log.i(TAG, "Daily index backup skipped: the vault is active on another phone")
      Result.success()
    } catch (error: Throwable) {
      Log.w(TAG, "Daily index backup failed (attempt ${runAttemptCount + 1}): ${error.message}")
      if (runAttemptCount < MAX_ATTEMPTS) Result.retry() else Result.failure()
    }
  }

  companion object {
    private const val TAG = "AmbryIndexBackup"
    private const val WORK_NAME = "ambry/DailyIndexBackup"
    private const val MAX_ATTEMPTS = 3

    /** Idempotent: keeps an already scheduled daily job (and its timing) as it is. */
    fun schedule(context: Context) {
      val request = PeriodicWorkRequestBuilder<IndexBackupWorker>(1, TimeUnit.DAYS)
        .setConstraints(
          Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresBatteryNotLow(true)
            .build()
        )
        .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.MINUTES)
        .build()
      WorkManager.getInstance(context).enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
    }
  }
}
