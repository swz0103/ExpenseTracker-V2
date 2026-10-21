package io.github.swz0103.expensetracker

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * The app's notifications (lib/src/notifications.dart): each alert is an
 * alarm that posts it when due. The alerts are kept in preferences, so a
 * restart of the phone schedules them again.
 */
object Reminders {
    private const val CHANNEL = "reminders"
    private const val PREFS = "reminders"
    private const val KEY = "alerts"
    const val EXTRA_TITLE = "title"
    const val EXTRA_TEXT = "text"
    const val EXTRA_ID = "id"

    /** Replaces every alert still to come with [alerts]. */
    fun replace(context: Context, alerts: List<Map<String, Any?>>) {
        val kept = JSONArray()
        for (alert in alerts) {
            val at = (alert["at"] as? Number)?.toLong() ?: continue
            kept.put(
                JSONObject()
                    .put("at", at)
                    .put("title", alert["title"] as? String ?: "")
                    .put("text", alert["text"] as? String ?: "")
                    .put("quick", alert["quick"] as? String ?: ""),
            )
        }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val before = JSONArray(prefs.getString(KEY, "[]"))
        for (i in 0 until before.length()) cancel(context, i)
        prefs.edit().putString(KEY, kept.toString()).apply()
        scheduleKept(context)
    }

    /** Sets an alarm for each kept alert still to come. */
    fun scheduleKept(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val kept = JSONArray(prefs.getString(KEY, "[]"))
        val now = System.currentTimeMillis()
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (i in 0 until kept.length()) {
            val alert = kept.getJSONObject(i)
            val at = alert.getLong("at")
            if (at <= now) continue
            alarms.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                at,
                pending(context, i, alert),
            )
        }
    }

    private fun pending(context: Context, id: Int, alert: JSONObject?): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java).putExtra(EXTRA_ID, id)
        if (alert != null) {
            intent.putExtra(EXTRA_TITLE, alert.optString("title"))
                .putExtra(EXTRA_TEXT, alert.optString("text"))
                .putExtra(MainActivity.EXTRA_QUICK, alert.optString("quick"))
        }
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun cancel(context: Context, id: Int) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarms.cancel(pending(context, id, null))
    }

    /** Whether notifications may be posted. */
    fun allowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    /** Posts one alert; tapping it opens the app, or the composer. */
    fun show(context: Context, id: Int, title: String, text: String, quick: String) {
        if (!allowed(context)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "提醒", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "定期扣款、卡費與記帳提醒"
                },
            )
        }
        // Request codes from 1000 on, apart from the widget's.
        val tap = MainActivity.opening(context, quick, 1000 + id)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(tap)
            .setAutoCancel(true)
            // Amounts stay off the lock screen.
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(
                NotificationCompat.Builder(context, CHANNEL)
                    .setSmallIcon(R.drawable.ic_notification)
                    .setContentTitle("記帳本")
                    .setContentText("有一則提醒")
                    .build(),
            )
            .build()
        manager.notify(id, notification)
    }
}

/** Posts an alert when its alarm goes off. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Reminders.show(
            context,
            intent.getIntExtra(Reminders.EXTRA_ID, 0),
            intent.getStringExtra(Reminders.EXTRA_TITLE) ?: return,
            intent.getStringExtra(Reminders.EXTRA_TEXT) ?: "",
            intent.getStringExtra(MainActivity.EXTRA_QUICK) ?: "",
        )
    }
}

/**
 * Sets the alarms again after the phone restarts or the app updates, and
 * when the clock or time zone changes, so each alert still comes at its
 * time.
 */
class RestartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            -> Reminders.scheduleKept(context)
        }
    }
}
