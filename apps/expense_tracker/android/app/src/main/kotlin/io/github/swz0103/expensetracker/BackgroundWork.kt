package io.github.swz0103.expensetracker

import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import java.io.IOException
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean

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
     * The market job runs on any network (D40): what it fetches is small,
     * and a stale price makes the figures wrong, which costs more than the
     * data. It still waits out a low battery and backs off after a failure.
     */
    val MARKET_NETWORK = NetworkType.CONNECTED

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
        return when (val cause = causeOf(error)) {
            is DriveUploader.NotAllowed -> false
            is DriveUploader.Refused -> cause.status == 429 || cause.status in 500..599
            // Play services did not answer in time, or could not reach Google.
            is TimeoutException -> true
            is ApiException -> cause.statusCode in PASSING_STATUSES
            else -> cause is IOException
        }
    }

    /**
     * What went wrong under [error]: Play services' tasks (`Tasks.await`)
     * wrap their failure in an [ExecutionException].
     */
    fun causeOf(error: Throwable): Throwable =
        if (error is ExecutionException) error.cause ?: error else error

    /** Play services' failures that pass by themselves: no network, too slow, or its own hiccup. */
    private val PASSING_STATUSES = setOf(
        CommonStatusCodes.NETWORK_ERROR,
        CommonStatusCodes.TIMEOUT,
        CommonStatusCodes.INTERNAL_ERROR,
    )

    /**
     * WorkManager stopped the run (it ran too long, or its conditions no
     * longer hold): it ends where it is, writes nothing more, and is run
     * again later.
     */
    class Stopped : Exception("The run was stopped.")

    /**
     * One run of a job at a time in this process: WorkManager may start
     * the next run while a stopped one has not yet seen it was stopped.
     */
    class OneAtATime {
        private val busy = AtomicBoolean(false)

        /** [work]'s value, or [whenBusy] without running it while another run is under way. */
        fun <T> run(whenBusy: T, work: () -> T): T {
            if (!busy.compareAndSet(false, true)) return whenBusy
            try {
                return work()
            } finally {
                busy.set(false)
            }
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
