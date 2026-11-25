package io.github.swz0103.expensetracker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * Looks once a day, without the app being opened, for a newer version on
 * the release the APKs are published on, and says so in one notification
 * per new build; tapping it opens the app, where 關於 downloads it. Only
 * `update.json` is fetched; nothing of the ledger is read or sent.
 *
 * It follows 自動檢查新版本 in 關於 (`updateChecks` in background.json, which
 * only the app writes) and does nothing in a build made by hand, whose
 * version code is 1 (lib/src/features/settings/model/app_update.dart).
 */
class UpdateWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        try {
            look()
        } catch (e: Exception) {
            // Tried again tomorrow.
        }
        return Result.success()
    }

    private fun look() {
        val context = applicationContext
        val settings = File(context.filesDir, AppFiles.BACKGROUND)
        val on = try {
            !settings.exists() || JSONObject(settings.readText()).optBoolean("updateChecks", true)
        } catch (e: Exception) {
            true
        }
        if (!on) return
        val current = currentBuild(context)
        if (current <= 1) return
        val info = fetch(URL(INFO_URL))
        val newest = UpdateFeed.build(info) ?: return
        val kept = context.getSharedPreferences(NAME, Context.MODE_PRIVATE)
        if (!UpdateFeed.worthSaying(current, newest, kept.getInt(SAID, 0))) return
        notify(context, UpdateFeed.version(info))
        kept.edit().putInt(SAID, newest).apply()
    }

    private fun fetch(url: URL): String {
        val connection = url.openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 15_000
        connection.instanceFollowRedirects = true
        return try {
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    private fun notify(context: Context, version: String?) {
        if (!Reminders.allowed(context)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, NativeWords.UPDATE_CHANNEL, NotificationManager.IMPORTANCE_LOW).apply {
                    description = NativeWords.UPDATE_CHANNEL_ABOUT
                },
            )
        }
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            // The app is not running to word it: NativeWords holds its words.
            .setContentTitle(
                if (version == null) NativeWords.UPDATE_TITLE else NativeWords.UPDATE_TITLE_OF.format(version),
            )
            .setContentText(NativeWords.UPDATE_TEXT)
            .setContentIntent(MainActivity.opening(context, "", 900))
            .setAutoCancel(true)
            .build()
        manager.notify(NAME, 900, notification)
    }

    companion object {
        private const val NAME = "updates"
        private const val SAID = "said"
        private const val CHANNEL = "updates"
        private const val INFO_URL =
            "https://github.com/swz0103/ExpenseTracker-V2/releases/latest/download/update.json"

        /** Looks about once a day while there is a network. */
        fun schedule(context: Context) {
            val request = PeriodicWorkRequest.Builder(UpdateWorker::class.java, 1, TimeUnit.DAYS)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .setRequiresBatteryNotLow(true)
                        .build(),
                )
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        private fun currentBuild(context: Context): Long {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            @Suppress("DEPRECATION")
            return if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        }
    }
}

/** What the job decides, kept apart from Android to be tested. */
internal object UpdateFeed {
    private val buildField = Regex("\"build\"\\s*:\\s*(\\d+)")
    private val versionField = Regex("\"version\"\\s*:\\s*\"(\\d+\\.\\d+\\.\\d+)\"")

    /** The build `update.json` names; null for anything else. Read
     *  without org.json, which unit tests do not have. */
    fun build(text: String): Int? =
        buildField.find(text)?.groupValues?.get(1)?.toIntOrNull()

    /** The version `update.json` names, as the app shows it (0.20.0);
     *  null when it names none. */
    fun version(text: String): String? = versionField.find(text)?.groupValues?.get(1)

    /** Said once per newer build: not again for one already said. */
    fun worthSaying(current: Long, newest: Int, said: Int): Boolean =
        newest > current && newest != said
}
