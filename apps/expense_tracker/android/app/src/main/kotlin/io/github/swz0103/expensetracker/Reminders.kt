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
import java.util.Calendar

/**
 * The app's notifications (lib/src/features/reminders/model/notifications.dart): each alert is an
 * alarm that posts it when due. The alerts are kept in preferences, so a
 * restart of the phone schedules them again.
 *
 * Each alert is due at a time on the wall clock (a date, hour and minute),
 * not at a fixed instant: after the time zone or the clock changes, the
 * alarms are worked out again from the clock, so 9:00 stays 9:00 where the
 * phone now is. The alarms are inexact (setAndAllowWhileIdle), so Android
 * may post one some minutes late while the phone sleeps (Doze), unless
 * the person asked for reminders on the minute and allowed the app's
 * alarms (setExactAndAllowWhileIdle).
 *
 * Each alert carries a tag (`nudge`, `due:<key>`). A notification already
 * showing whose tag the app no longer lists as wanted is taken away: the
 * daily nudge once something was recorded, a due date once it was booked
 * or paid.
 *
 * What is kept is what the notification shows (its title and text, which
 * can name an amount) and which screen tapping it opens. The preferences
 * stay on the phone: they are not in the cloud backup or a device
 * transfer (res/xml/data_extraction_rules.xml only includes files).
 */
object Reminders {
    private const val CHANNEL = "reminders"
    private const val PREFS = "reminders"
    private const val KEY = "alerts"
    private const val EXACT = "exact"
    const val EXTRA_TAG = "tag"

    /** The test notification's alarm, apart from the kept alerts'. */
    private const val TEST_ID = 990
    const val EXTRA_TITLE = "title"
    const val EXTRA_TEXT = "text"
    const val EXTRA_ID = "id"

    /** An alert's wall-clock time: year, month (1-12), day, hour, minute. */
    private val CLOCK_FIELDS = listOf("y", "m", "d", "hour", "minute")

    /**
     * Replaces every alert still to come with [alerts], on the minute when
     * [exact]; and takes away those showing whose tag is not [wanted].
     */
    fun replace(
        context: Context,
        alerts: List<Map<String, Any?>>,
        exact: Boolean = false,
        wanted: Set<String>? = null,
    ) {
        val kept = JSONArray()
        for (alert in alerts) {
            val at = (alert["at"] as? Number)?.toLong() ?: continue
            val entry = JSONObject()
                .put("at", at)
                .put("title", alert["title"] as? String ?: "")
                .put("text", alert["text"] as? String ?: "")
                .put("quick", alert["quick"] as? String ?: "")
                .put("tag", alert["tag"] as? String ?: "")
            // The wall-clock time, when the app sends it (it always does
            // now); without it the alert keeps its instant [at].
            val clock = CLOCK_FIELDS.mapNotNull { name ->
                (alert[name] as? Number)?.toInt()?.let { name to it }
            }
            if (clock.size == CLOCK_FIELDS.size) {
                for ((name, value) in clock) entry.put(name, value)
            }
            kept.put(entry)
        }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val before = JSONArray(prefs.getString(KEY, "[]"))
        for (i in 0 until before.length()) cancel(context, i)
        prefs.edit().putString(KEY, kept.toString()).putBoolean(EXACT, exact).apply()
        scheduleKept(context)
        if (wanted != null) clearShown(context, wanted)
    }

    /** Takes away the app's notifications showing whose tag is not [wanted]. */
    private fun clearShown(context: Context, wanted: Set<String>) {
        if (Build.VERSION.SDK_INT < 23) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        for (shown in manager.activeNotifications) {
            val tag = shown.tag ?: continue
            if (tag !in wanted) manager.cancel(tag, shown.id)
        }
    }

    /** Whether alarms may go off on the minute. */
    fun exactAllowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarms.canScheduleExactAlarms()
    }

    /** Sets [intent]'s alarm for [at], on the minute when asked and allowed. */
    private fun setAlarm(context: Context, at: Long, intent: PendingIntent, exact: Boolean) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (exact && exactAllowed(context)) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        }
    }

    /** A test notification in a minute, as the reminders would come. */
    fun test(context: Context, exact: Boolean) {
        val intent = Intent(context, ReminderReceiver::class.java)
            .putExtra(EXTRA_ID, TEST_ID)
            .putExtra(EXTRA_TITLE, "測試通知")
            .putExtra(EXTRA_TEXT, "提醒會像這樣出現。")
            .putExtra(EXTRA_TAG, "test")
            .putExtra(MainActivity.EXTRA_QUICK, "")
        val pending = PendingIntent.getBroadcast(
            context,
            TEST_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        setAlarm(context, System.currentTimeMillis() + 60_000, pending, exact)
    }

    /**
     * When [alert] is due, in milliseconds: its wall-clock time in the
     * phone's time zone now, or the instant it was given when it carries
     * no wall-clock time (alerts kept by an older version).
     */
    private fun dueAt(alert: JSONObject): Long {
        if (!alert.has("y")) return alert.getLong("at")
        return Calendar.getInstance().apply {
            clear()
            set(
                alert.getInt("y"),
                alert.getInt("m") - 1,
                alert.getInt("d"),
                alert.getInt("hour"),
                alert.getInt("minute"),
            )
        }.timeInMillis
    }

    /**
     * Sets an alarm for each kept alert still to come, at its time on the
     * clock now; one whose time has passed (after the clock moved ahead)
     * loses its alarm.
     */
    fun scheduleKept(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val kept = JSONArray(prefs.getString(KEY, "[]"))
        val now = System.currentTimeMillis()
        val exact = prefs.getBoolean(EXACT, false)
        for (i in 0 until kept.length()) {
            val alert = kept.getJSONObject(i)
            val at = dueAt(alert)
            if (at <= now) {
                cancel(context, i)
                continue
            }
            // The same request code replaces an alarm set before.
            setAlarm(context, at, pending(context, i, alert), exact)
        }
    }

    private fun pending(context: Context, id: Int, alert: JSONObject?): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java).putExtra(EXTRA_ID, id)
        if (alert != null) {
            intent.putExtra(EXTRA_TITLE, alert.optString("title"))
                .putExtra(EXTRA_TEXT, alert.optString("text"))
                .putExtra(MainActivity.EXTRA_QUICK, alert.optString("quick"))
                .putExtra(EXTRA_TAG, alert.optString("tag"))
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
    fun show(
        context: Context,
        id: Int,
        title: String,
        text: String,
        quick: String,
        tag: String = "",
    ) {
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
        // Tagged, so one no longer wanted can be taken away.
        manager.notify(tag.ifEmpty { null }, id, notification)
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
            intent.getStringExtra(Reminders.EXTRA_TAG) ?: "",
        )
    }
}

/**
 * Sets the alarms again after the phone restarts or the app updates, and
 * when the clock or time zone changes: each alert's time is worked out
 * again from its wall-clock time, in the time zone the phone is in now.
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
