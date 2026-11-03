package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Test

/** 本月概況 shows this month's snapshot, and never last month's as this one's. */
class WidgetViewTest {
    private val week = listOf(0, 100, -1, -1, -1, -1, -1)
    private val snapshot = WidgetView.Snapshot(
        "2026-10", "10 月支出", "12,345", "剩 7,655", 62,
        budget = "預算 20,000", pace = 65, week = week, weekTotal = "12,345", today = 1,
        shortLabel = "10 月預算剩", shortFigure = "7,655",
    )

    @Test
    fun thisMonthsSnapshotIsShownAsWritten() {
        assertEquals(
            WidgetView.Shown(
                "10 月支出", "12,345", "剩 7,655", 62,
                budget = "預算 20,000", pace = 65, week = week, weekTotal = "12,345", today = 1,
                shortLabel = "10 月預算剩", shortFigure = "7,655",
            ),
            WidgetView.of(snapshot, "2026-10"),
        )
    }

    @Test
    fun aSnapshotWithoutTheWeekStillShows() {
        val shown = WidgetView.of(WidgetView.Snapshot("2026-10", "10 月預算", "已用 62%", "", 62), "2026-10")
        assertEquals(null, shown.week)
        assertEquals("10 月預算", shown.shortLabel)
        assertEquals("已用 62%", shown.shortFigure)
    }

    @Test
    fun anOlderMonthAsksForTheApp() {
        val shown = WidgetView.of(snapshot, "2026-11")
        assertEquals("—", shown.figure)
        assertEquals(null, shown.progress)
        assertEquals(null, shown.week)
        assertEquals("—", shown.shortFigure)
    }

    @Test
    fun withoutASnapshotItSaysWhereToTurnFiguresOn() {
        assertEquals(null, WidgetView.of(null, "2026-10").progress)
    }

    @Test
    fun progressStaysWithinTheBar() {
        val shown = WidgetView.of(snapshot.copy(progress = 140, pace = 120), "2026-10")
        assertEquals(100, shown.progress)
        assertEquals(100, shown.pace)
    }

    // Written on Tuesday 2026-10-20: Monday nothing, Tuesday the most.
    private val written = snapshot.copy(date = "2026-10-20")

    @Test
    fun daysCountFromMonday() {
        assertEquals(1, WidgetView.Day(2026, 10, 20).weekday)
        assertEquals(6, WidgetView.Day(2026, 11, 1).weekday)
        assertEquals(20381L, WidgetView.Day(2025, 10, 20).epoch)
    }

    @Test
    fun laterThatWeekTheDaysSinceAreEmpty() {
        val shown = WidgetView.of(written, "2026-10", WidgetView.Day(2026, 10, 22))
        assertEquals(listOf(0, 100, 0, 0, -1, -1, -1), shown.week)
        assertEquals(3, shown.today)
        assertEquals("12,345", shown.weekTotal)
        assertEquals(71, shown.pace)
    }

    @Test
    fun aNewWeekStartsEmpty() {
        val shown = WidgetView.of(written, "2026-10", WidgetView.Day(2026, 10, 28))
        assertEquals(listOf(0, 0, 0, -1, -1, -1, -1), shown.week)
        assertEquals(2, shown.today)
        assertEquals("0", shown.weekTotal)
    }

    @Test
    fun theSameDayOrABackwardClockChangesNothing() {
        assertEquals(week, WidgetView.of(written, "2026-10", WidgetView.Day(2026, 10, 20)).week)
        assertEquals(week, WidgetView.of(written, "2026-10", WidgetView.Day(2026, 10, 19)).week)
        assertEquals(week, WidgetView.of(snapshot, "2026-10", WidgetView.Day(2026, 10, 22)).week)
    }
}
