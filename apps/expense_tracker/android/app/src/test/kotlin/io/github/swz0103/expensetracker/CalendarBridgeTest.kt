package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** REM-04: the app's events are found again by the key on their last line. */
class CalendarBridgeTest {
    @Test
    fun aDescriptionGivesBackItsNoteAndKey() {
        val written = CalendarBridge.describe("定期交易，扣款帳戶：銀行", "r:gym:2026-12-5")
        assertEquals("定期交易，扣款帳戶：銀行\n記帳本#r:gym:2026-12-5", written)
        assertEquals("定期交易，扣款帳戶：銀行" to "r:gym:2026-12-5", CalendarBridge.split(written))
    }

    @Test
    fun aNoteOfManyLinesKeepsThem() {
        val written = CalendarBridge.describe("第一行\n第二行", "c:card:2026-11-5")
        assertEquals("第一行\n第二行" to "c:card:2026-11-5", CalendarBridge.split(written))
    }

    @Test
    fun theirOwnEventsAreNotTheApps() {
        assertNull(CalendarBridge.split(null))
        assertNull(CalendarBridge.split("看牙醫"))
        // The mark not on the last line: someone's note quoting it.
        assertNull(CalendarBridge.split("備註\n記帳本#r:gym:2026-12-5\n我的筆記"))
    }
}
