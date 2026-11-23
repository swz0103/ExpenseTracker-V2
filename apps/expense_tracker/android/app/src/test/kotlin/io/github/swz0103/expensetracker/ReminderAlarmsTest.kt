package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** D45: each alarm on the minute has an inexact twin, within Android's limit. */
class ReminderAlarmsTest {
    @Test
    fun theAppsCapWithTwinsStaysUnderAndroidsLimit() {
        // The app asks for at most 160 alerts (ReminderTiming.most in
        // reminder_rules.dart): 160 * 2 = 320 alarms, plus the test
        // notification's one = 321, under the 500 Android allows.
        assertEquals(320, ReminderAlarms.alarms(160, exact = true))
        assertEquals(160, ReminderAlarms.alarms(160, exact = false))
        assertEquals(500, ReminderAlarms.ANDROID_LIMIT)
        assertTrue(ReminderAlarms.alarms(160, exact = true) + 1 <= ReminderAlarms.ANDROID_LIMIT)
    }

    @Test
    fun theGuardKeepsEveryPlanWithinTheLimit() {
        // (500 - 1) / 2 = 249 alerts: 498 alarms and the test's = 499.
        assertEquals(249, ReminderAlarms.MOST_ALERTS)
        assertEquals(498, ReminderAlarms.alarms(ReminderAlarms.MOST_ALERTS, exact = true))
        assertTrue(160 <= ReminderAlarms.MOST_ALERTS)
    }

    @Test
    fun theTwinsHaveRequestCodesOfTheirOwn() {
        assertEquals(3000, ReminderAlarms.twinCode(0))
        assertEquals(3248, ReminderAlarms.twinCode(248))
        val last = ReminderAlarms.MOST_ALERTS - 1
        // Alarms 0..248, the test's 990, taps 1000..1248, 「確認入帳」
        // 2000..2248, twins 3000..3248: no two the same.
        val codes = (0..last).toList() +
            ReminderAlarms.TEST_CODE +
            (0..last).map { 1000 + it } +
            (0..last).map { 2000 + it } +
            (0..last).map { ReminderAlarms.twinCode(it) }
        // 249 * 4 + 1 = 997.
        assertEquals(997, codes.toSet().size)
    }

    @Test
    fun theSecondOfThePairPostsNothing() {
        val at = 1_000_000L
        val grace = 3_600_000L
        // The exact alarm goes off on time and posts.
        assertEquals(ReminderGrace.Step.POST_NOW, ReminderGrace.step(at, grace, at, posted = false))
        // Its twin goes off later (Doze), finds it posted: nothing more.
        assertEquals(ReminderGrace.Step.DONE, ReminderGrace.step(at, grace, at + 600_000L, posted = true))
        // With the exact one cancelled by Android, the twin alone posts.
        assertEquals(ReminderGrace.Step.POST_NOW, ReminderGrace.step(at, grace, at + 600_000L, posted = false))
    }
}
