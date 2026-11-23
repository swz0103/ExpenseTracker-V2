package io.github.swz0103.expensetracker

import io.github.swz0103.expensetracker.ReminderGrace.Step
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * AND-02, AND-03: what becomes of a kept alert when the plan is armed
 * again (a restart, an update, a time zone or clock change, alarms on the
 * minute allowed) or its alarm goes off.
 */
class ReminderGraceTest {
    private val hour = 3_600_000L

    /** 09:00, the time of the alert in each case. */
    private val nine = 1_795_051_800_000L

    @Test
    fun anAlertStillToComeIsArmed() {
        assertEquals(Step.ARM, ReminderGrace.step(nine, 12 * hour, nine - 1, posted = false))
    }

    @Test
    fun anAlertMissedWithinItsGraceIsPostedAtOnce() {
        // Off at 08:30, on again at 09:40: 40 minutes late, within 7 days.
        val sevenDays = 7 * 24 * hour
        assertEquals(Step.POST_NOW, ReminderGrace.step(nine, sevenDays, nine + 40 * 60_000L, posted = false))
        // Exactly its grace late still counts.
        assertEquals(Step.POST_NOW, ReminderGrace.step(nine, 3 * hour, nine + 3 * hour, posted = false))
        // Its own time, when the clock reads it exactly.
        assertEquals(Step.POST_NOW, ReminderGrace.step(nine, 0, nine, posted = false))
    }

    @Test
    fun anAlertMissedLongerAgoThanItsGraceIsDropped() {
        // A nudge with 3 hours of grace, the phone back 3 hours and a
        // millisecond later.
        assertEquals(Step.DROP, ReminderGrace.step(nine, 3 * hour, nine + 3 * hour + 1, posted = false))
        // An alert of an earlier version has no grace.
        assertEquals(Step.DROP, ReminderGrace.step(nine, 0, nine + 1, posted = false))
    }

    @Test
    fun anAlertPostedIsNotPostedAgain() {
        assertEquals(Step.DONE, ReminderGrace.step(nine, 12 * hour, nine + hour, posted = true))
        assertEquals(Step.DONE, ReminderGrace.step(nine, 12 * hour, nine - hour, posted = true))
    }

    @Test
    fun thePostedAreForgottenOnceTheirAlertLeavesThePlan() {
        assertEquals(
            setOf("due|due:r:gym:2026-11-20|2026-11-20"),
            ReminderGrace.keptPosted(
                setOf("due|due:r:gym:2026-11-20|2026-11-20", "nudge|nudge|2026-11-19"),
                listOf("due|due:r:gym:2026-11-20|2026-11-20", "nudge|nudge|2026-11-24"),
            ),
        )
    }

    @Test
    fun thePlanIsArmedAgainOnEachBroadcastTheManifestLists() {
        assertEquals(
            setOf(
                "android.intent.action.BOOT_COMPLETED",
                "android.intent.action.MY_PACKAGE_REPLACED",
                "android.intent.action.TIMEZONE_CHANGED",
                "android.intent.action.TIME_SET",
                "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED",
            ),
            RestartReceiver.ACTIONS,
        )
        val manifest = File("src/main/AndroidManifest.xml").readText()
        val receiver = manifest.substringAfter("android:name=\".RestartReceiver\"").substringBefore("</receiver>")
        for (action in RestartReceiver.ACTIONS) {
            assertTrue(action, receiver.contains("<action android:name=\"$action\"/>"))
        }
    }
}
