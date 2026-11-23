package io.github.swz0103.expensetracker

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Asking to post notifications, and handing the alerts to `Reminders.kt`
 * (lib/src/app/android/notification_adapter.dart).
 */
class RemindersHandler(private val activity: FragmentActivity) : ChannelHandler {
    private var pendingNotify: MethodChannel.Result? = null

    /** Asks once to post notifications (Android 13 and later). */
    private val askNotify =
        activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            val result = pendingNotify ?: return@registerForActivityResult
            pendingNotify = null
            result.success(granted && Reminders.allowed(activity))
        }

    /** Opens a page of the system settings; a phone without it shows none. */
    private fun openSettings(intent: Intent) {
        try {
            activity.startActivity(intent)
        } catch (e: Exception) {
            // Nothing to open: the status row still says how it stands.
        }
    }

    /** The notification channels the app sends with a call: id, name, about. */
    private fun channels(call: MethodCall): List<Map<String, Any?>> =
        call.argument<List<Map<String, Any?>>>("channels") ?: emptyList()

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
                    Reminders.replace(
                        activity,
                        alerts,
                        exact = call.argument<Boolean>("exact") == true,
                        wanted = call.argument<List<String>>("wanted")?.toSet(),
                        channels = channels(call),
                        retired = call.argument<List<String>>("retired") ?: emptyList(),
                    )
                    result.success(null)
                }
            }
            "showNotification" -> {
                val title = call.argument<String>("title")
                val text = call.argument<String>("text")
                if (title == null || text == null) {
                    result.error("bad-arguments", "title and text are required", null)
                } else {
                    Reminders.ensureChannels(activity, channels(call))
                    Reminders.show(
                        activity,
                        call.argument<Int>("id") ?: 700,
                        title,
                        text,
                        call.argument<String>("quick") ?: "",
                        call.argument<String>("tag") ?: "",
                        channel = call.argument<String>("channel") ?: "",
                    )
                    result.success(null)
                }
            }
            "testNotification" -> {
                Reminders.ensureChannels(activity, channels(call))
                Reminders.test(
                    activity,
                    exact = call.argument<Boolean>("exact") == true,
                    channel = call.argument<String>("channel") ?: "",
                    title = call.argument<String>("title") ?: "",
                    text = call.argument<String>("text") ?: "",
                )
                result.success(null)
            }
            "reminderStatus" -> {
                val power = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(
                    mapOf(
                        "notifications" to Reminders.allowed(activity),
                        "exact" to Reminders.exactAllowed(activity),
                        "battery" to (Build.VERSION.SDK_INT < 23 ||
                            power.isIgnoringBatteryOptimizations(activity.packageName)),
                    ),
                )
            }
            "openExactSettings" -> {
                // Android 12 and later ask in the system settings; before,
                // alarms on the minute need no asking.
                if (Build.VERSION.SDK_INT >= 31) {
                    val intent = Intent(
                        Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                        Uri.parse("package:${activity.packageName}"),
                    )
                    openSettings(intent)
                }
                result.success(null)
            }
            "openBatterySettings" -> {
                // The app's own page, where its battery use is chosen
                // (「電池」 › 不受限制). Asking straight away to be left out
                // of battery saving needs a permission Google Play allows
                // only some kinds of app, so it is not asked for.
                openSettings(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:${activity.packageName}"),
                    ),
                )
                result.success(null)
            }
            else -> return false
        }
        return true
    }
}
