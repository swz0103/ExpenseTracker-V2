package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.TimeZone

/** A reminder rings at its time on the phone's clock (Reminders.kt). */
class RemindersTest {
    private val taipei = TimeZone.getTimeZone("Asia/Taipei")
    private val utc = TimeZone.getTimeZone("UTC")

    @Test
    fun theMonthCountsFromOneAsTheAppWritesIt() {
        // 2026-11-19 09:30 in Taipei is 01:30 UTC.
        assertEquals(1_795_051_800_000L, Reminders.wallClock(2026, 11, 19, 9, 30, taipei))
    }

    @Test
    fun theSameTimeOnAnotherClockIsAnotherInstant() {
        val inTaipei = Reminders.wallClock(2026, 1, 1, 8, 0, taipei)
        val inUtc = Reminders.wallClock(2026, 1, 1, 8, 0, utc)
        assertEquals(8 * 60 * 60 * 1000L, inUtc - inTaipei)
    }

    @Test
    fun secondsAreLeftAtZero() {
        assertEquals(0L, Reminders.wallClock(2026, 3, 5, 7, 15, utc) % 60_000)
    }
}
