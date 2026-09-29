package dev.expensetracker.preview

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.util.Calendar

/** Stores only the user's opt-in; the alarm and notification contain no ledger data. */
internal object RecurringReminderScheduler {
    private const val preferences = "expense_v2_recurring_reminder_v1"
    private const val enabledKey = "daily_check_enabled"
    private const val channelId = "expense_v2_recurring_check_v1"
    private const val reminderAction = "dev.expensetracker.preview.RECURRING_CHECK"
    private const val notificationId = 501

    fun configured(context: Context): Boolean =
        context.getSharedPreferences(preferences, Context.MODE_PRIVATE).getBoolean(enabledKey, false)

    fun canNotify(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        ensureChannel(manager)
        return manager.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 26 ||
                manager.getNotificationChannel(channelId)?.importance != NotificationManager.IMPORTANCE_NONE)
    }

    fun isEnabled(context: Context): Boolean = configured(context) && canNotify(context)

    fun setEnabled(context: Context, enabled: Boolean): Boolean {
        if (enabled && !canNotify(context)) return false
        context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
            .edit().putBoolean(enabledKey, enabled).commit()
            .also { check(it) { "Reminder setting was not saved" } }
        if (enabled) {
            try {
                schedule(context)
            } catch (failure: Exception) {
                context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
                    .edit().putBoolean(enabledKey, false).commit()
                throw failure
            }
        } else {
            cancel(context)
        }
        return enabled
    }

    fun schedule(context: Context) {
        if (!configured(context)) return
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 9)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarms.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            next.timeInMillis,
            AlarmManager.INTERVAL_DAY,
            alarmIntent(context),
        )
    }

    private fun cancel(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarms.cancel(alarmIntent(context))
        context.getSystemService(NotificationManager::class.java).cancel(notificationId)
    }

    private fun alarmIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        notificationId,
        Intent(context, RecurringReminderReceiver::class.java).setAction(reminderAction),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun deliver(context: Context) {
        if (!isEnabled(context)) return
        val open = PendingIntent.getActivity(
            context,
            notificationId,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(context, channelId) else Notification.Builder(context)
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("記帳 V2")
            .setContentText("檢查定期交易；入帳前仍需逐筆確認。")
            .setContentIntent(open)
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_SECRET)
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(notificationId, notification)
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(channelId, "定期交易檢查", NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
    }

    fun isReminderAction(action: String?): Boolean = action == reminderAction
}

class RecurringReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                RecurringReminderScheduler.schedule(context)
            else -> if (RecurringReminderScheduler.isReminderAction(intent.action))
                RecurringReminderScheduler.deliver(context)
        }
    }
}
