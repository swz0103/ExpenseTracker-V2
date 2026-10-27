package io.github.swz0103.expensetracker

import android.Manifest
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Asking to post notifications, and handing the alerts to `Reminders.kt`
 * (lib/src/app/android/notifications.dart).
 */
class RemindersPart(private val activity: FragmentActivity) : ChannelPart {
    private var pendingNotify: MethodChannel.Result? = null

    /** Asks once to post notifications (Android 13 and later). */
    private val askNotify =
        activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            val result = pendingNotify ?: return@registerForActivityResult
            pendingNotify = null
            result.success(granted && Reminders.allowed(activity))
        }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "notificationAccess" -> {
                if (Reminders.allowed(activity)) {
                    result.success(true)
                } else if (Build.VERSION.SDK_INT < 33) {
                    // Turned off in the system settings: only the person
                    // can turn it back on there.
                    result.success(false)
                } else if (pendingNotify != null) {
                    result.error("busy", "Already asking.", null)
                } else {
                    pendingNotify = result
                    launchOr(result, { pendingNotify = null }) {
                        askNotify.launch(Manifest.permission.POST_NOTIFICATIONS)
                    }
                }
            }
            "scheduleNotifications" -> {
                val alerts = call.argument<List<Map<String, Any?>>>("alerts")
                if (alerts == null) {
                    result.error("bad-arguments", "alerts are required", null)
                } else {
                    Reminders.replace(activity, alerts)
                    result.success(null)
                }
            }
            else -> return false
        }
        return true
    }
}
