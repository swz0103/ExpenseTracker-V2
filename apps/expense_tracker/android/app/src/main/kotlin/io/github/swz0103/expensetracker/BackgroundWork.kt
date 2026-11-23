package io.github.swz0103.expensetracker

import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * What the background jobs cost, in one place for both ([MarketWorker],
 * [BackupWorker]; AND-05): the network each needs, never while the battery
 * is low, and a failed run tried again after a wait that doubles each time
 * rather than at the next period, or never.
 */
internal object BackgroundWork {
    /** The first wait after a failed run; WorkManager doubles it each time. */
    const val BACKOFF_MINUTES = 15L

    /** How many runs in a row may fail on the network before it is noted for the app. */
    const val RETRIES = 3

    /**
     * The exchanges' day lists are a few MiB each: the background job
     * fetches them only on Wi-Fi or another network that costs nothing per
     * byte. On mobile data the app fetches what it needs when it is opened.
     */
    val MARKET_NETWORK = NetworkType.UNMETERED

    /**
     * The backups need a network only to reach Google Drive; the phone's
     * folder needs none. Backups with the receipt photos also wait for
     * Wi-Fi while the person keeps `photosOnWifi` on ([BackupWorker]).
     */
    fun backupNetwork(driveLinked: Boolean): NetworkType =
        if (driveLinked) NetworkType.CONNECTED else NetworkType.NOT_REQUIRED

    /**
     * Whether a run that failed on [error], the [attempt]th in a row
     * (from 0), is tried again rather than noted as failed: a network that
     * dropped, or Google busy (429, 5xx), while fewer than [RETRIES] runs
     * have failed. Access not given, or a refusal, is noted at once.
     */
    fun retries(error: Exception, attempt: Int): Boolean {
        if (attempt >= RETRIES) return false
        return when (error) {
            is DriveUploader.NotAllowed -> false
            is DriveUploader.Refused -> error.status == 429 || error.status in 500..599
            else -> error is IOException
        }
    }

    /** Only on [network], never while the battery is low. */
    fun constraints(network: NetworkType): Constraints =
        Constraints.Builder()
            .setRequiredNetworkType(network)
            .setRequiresBatteryNotLow(true)
            .build()

    /** Every [hours] hours on [network], with the back-off above. */
    fun periodic(worker: Class<out androidx.work.ListenableWorker>, hours: Long, network: NetworkType) =
        PeriodicWorkRequest.Builder(worker, hours, TimeUnit.HOURS)
            .setConstraints(constraints(network))
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_MINUTES, TimeUnit.MINUTES)
            .build()
}
