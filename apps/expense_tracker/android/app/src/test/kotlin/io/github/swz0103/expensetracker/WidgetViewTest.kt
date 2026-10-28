package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Test

/** 本月概況 shows this month's snapshot, and never last month's as this one's. */
class WidgetViewTest {
    private val snapshot = WidgetView.Snapshot("2026-10", "10 月支出", "12,345", "預算剩 7,655", 62)

    @Test
    fun thisMonthsSnapshotIsShownAsWritten() {
        assertEquals(
            WidgetView.Shown("10 月支出", "12,345", "預算剩 7,655", 62),
            WidgetView.of(snapshot, "2026-10"),
        )
    }

    @Test
    fun anOlderMonthAsksForTheApp() {
        val shown = WidgetView.of(snapshot, "2026-11")
        assertEquals("—", shown.figure)
        assertEquals(null, shown.progress)
    }

    @Test
    fun withoutASnapshotItSaysWhereToTurnFiguresOn() {
        assertEquals(null, WidgetView.of(null, "2026-10").progress)
    }

    @Test
    fun progressStaysWithinTheBar() {
        assertEquals(100, WidgetView.of(snapshot.copy(progress = 140), "2026-10").progress)
    }
}
