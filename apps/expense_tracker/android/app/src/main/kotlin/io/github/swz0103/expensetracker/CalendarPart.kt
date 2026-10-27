package io.github.swz0103.expensetracker

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The phone's calendars, where the ledger's due dates go
 * (`CalendarBridge.kt`, lib/src/app/android/calendar.dart).
 */
class CalendarPart(private val activity: FragmentActivity) : ChannelPart {
    private var pendingCalendar: MethodChannel.Result? = null

    /** Asks once for the calendar. */
    private val askCalendar =
        activity.registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
            val result = pendingCalendar ?: return@registerForActivityResult
            pendingCalendar = null
            result.success(granted.values.all { it })
        }

    private fun granted(): Boolean = PERMISSIONS.all {
        ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
    }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "calendarAccess" -> {
                if (granted()) {
                    result.success(true)
                } else if (pendingCalendar != null) {
                    result.error("busy", "Already asking.", null)
                } else {
                    pendingCalendar = result
                    launchOr(result, { pendingCalendar = null }) { askCalendar.launch(PERMISSIONS) }
                }
            }
            "calendars" -> {
                if (!granted()) {
                    result.error("no-access", "Calendar access was not given.", null)
                } else {
                    result.success(CalendarBridge.calendars(activity.contentResolver))
                }
            }
            "replaceCalendarEvents" -> {
                val calendar = (call.argument<Any>("calendar") as? Number)?.toLong()
                val from = (call.argument<Any>("from") as? Number)?.toLong()
                val events = call.argument<List<Map<String, Any?>>>("events")
                if (!granted()) {
                    result.error("no-access", "Calendar access was not given.", null)
                } else if (calendar == null || from == null || events == null) {
                    result.error("bad-arguments", "calendar, from and events are required", null)
                } else {
                    // Off the main thread: a calendar provider can be slow.
                    Thread {
                        try {
                            val written = CalendarBridge.replace(activity.contentResolver, calendar, from, events)
                            activity.runOnUiThread { result.success(written) }
                        } catch (e: Exception) {
                            activity.runOnUiThread { result.error("calendar", e.message, null) }
                        }
                    }.start()
                }
            }
            else -> return false
        }
        return true
    }

    private companion object {
        val PERMISSIONS = arrayOf(
            Manifest.permission.READ_CALENDAR,
            Manifest.permission.WRITE_CALENDAR,
        )
    }
}
