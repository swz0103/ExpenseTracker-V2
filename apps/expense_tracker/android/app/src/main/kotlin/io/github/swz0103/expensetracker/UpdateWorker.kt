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
 * It follows 自動更新 in 關於 (`updateChecks` in preferences.json, which
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
        val preferences = File(context.filesDir, "preferences.json")
        val on = try {
            !preferences.exists() || JSONObject(preferences.readText()).optBoolean("updateChecks", true)
        } catch (e: Exception) {
            true
        }
        if (!on) return
        val current = currentBuild(context)
        if (current <= 1) return
        val newest = UpdateFeed.build(fetch(URL(INFO_URL))) ?: return
        val kept = context.getSharedPreferences(NAME, Context.MODE_PRIVATE)
        if (!UpdateFeed.worthSaying(current, newest, kept.getInt(SAID, 0))) return
        notify(context, newest)
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

    private fun notify(context: Context, build: Int) {
        if (!Reminders.allowed(context)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "新版本", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "有新版本可以更新時"
                },
            )
        }
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("記帳本有新版本")
            .setContentText("第 $build 版，打開 App 到 設定 › 關於 更新")
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
            "https://github.com/swz0103/ExpenseTracker-V2/releases/download/android-latest/update.json"

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

    /** The build `update.json` names; null for anything else. Read
     *  without org.json, which unit tests do not have. */
    fun build(text: String): Int? =
        buildField.find(text)?.groupValues?.get(1)?.toIntOrNull()

    /** Said once per newer build: not again for one already said. */
    fun worthSaying(current: Long, newest: Int, said: Int): Boolean =
        newest > current && newest != said
}
