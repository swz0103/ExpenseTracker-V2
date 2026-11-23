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
 * (`CalendarBridge.kt`, lib/src/app/android/calendar_adapter.dart).
 */
class CalendarHandler(private val activity: FragmentActivity) : ChannelHandler {
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
            "calendarEvents" -> {
                val calendar = (call.argument<Any>("calendar") as? Number)?.toLong()
                val from = (call.argument<Any>("from") as? Number)?.toLong()
                if (!granted()) {
                    result.error("no-access", "Calendar access was not given.", null)
                } else if (calendar == null || from == null) {
                    result.error("bad-arguments", "calendar and from are required", null)
                } else {
                    offMain(result) { CalendarBridge.events(activity.contentResolver, calendar, from) }
                }
            }
            "applyCalendarChanges" -> {
                val calendar = (call.argument<Any>("calendar") as? Number)?.toLong()
                val insert = call.argument<List<Map<String, Any?>>>("insert")
                val update = call.argument<List<Map<String, Any?>>>("update")
                val delete = call.argument<List<Any?>>("delete")?.mapNotNull { (it as? Number)?.toLong() }
                if (!granted()) {
                    result.error("no-access", "Calendar access was not given.", null)
                } else if (calendar == null || insert == null || update == null || delete == null) {
                    result.error("bad-arguments", "calendar, insert, update and delete are required", null)
                } else {
                    offMain(result) {
                        CalendarBridge.apply(activity.contentResolver, calendar, insert, update, delete)
                    }
                }
            }
            else -> return false
        }
        return true
    }

    /** Runs [work] off the main thread, as a calendar provider can be slow,
     *  and answers with what it gives. */
    private fun offMain(result: MethodChannel.Result, work: () -> Any) {
        Thread {
            try {
                val answer = work()
                activity.runOnUiThread { result.success(answer) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("calendar", e.message, null) }
            }
        }.start()
    }

    private companion object {
        val PERMISSIONS = arrayOf(
            Manifest.permission.READ_CALENDAR,
            Manifest.permission.WRITE_CALENDAR,
        )
    }
}
