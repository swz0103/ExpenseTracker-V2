package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone

/** The background job's rules match the app's (phone_backup.dart). */
class BackupPlanTest {
    private val week = 7 * BackupPlan.DAY

    @Test
    fun aFirstBackupIsAlwaysDue() {
        assertTrue(BackupPlan.due(1_000, null, null, 3, week))
    }

    @Test
    fun aBackupWaitsForTheRhythmAndAChange() {
        val last = 1_000_000L
        assertFalse(BackupPlan.due(last + week - 1, last, 2, 3, week))
        assertFalse(BackupPlan.due(last + week, last, 3, 3, week))
        assertTrue(BackupPlan.due(last + week, last, 2, 3, week))
        assertTrue(BackupPlan.due(last + BackupPlan.DAY, last, 2, 3, BackupPlan.DAY))
    }

    @Test
    fun timesAreReadAsDartWritesThem() {
        assertEquals(1_793_156_645_123L, BackupPlan.millisOf("2026-10-28T03:04:05.123Z"))
        assertEquals(1_793_156_645_123L, BackupPlan.millisOf("2026-10-28T03:04:05.123456Z"))
        assertEquals(1_793_156_645_000L, BackupPlan.millisOf("2026-10-28T03:04:05Z"))
        assertNull(BackupPlan.millisOf(null))
        assertNull(BackupPlan.millisOf("null"))
        assertNull(BackupPlan.millisOf("not a time at all!!"))
    }

    @Test
    fun phoneNamesAreThoseOfTheApp() {
        val taipei = TimeZone.getTimeZone("Asia/Taipei")
        assertEquals(
            "記帳本-abc123-20261028-1104.etbk",
            BackupPlan.phoneName("abc123", 1_793_156_645_123L, taipei),
        )
    }

    @Test
    fun onlyThisLedgersOlderBackupsAreLetGo() {
        val ours = (1..7).map { "記帳本-abc123-2026100$it-0900.etbk" }
        val names = ours + listOf(
            "記帳本-zzz999-20260101-0900.etbk",
            "記帳本-abc123-notes.txt",
            "other.etbk",
        )
        assertEquals(
            listOf("記帳本-abc123-20261002-0900.etbk", "記帳本-abc123-20261001-0900.etbk"),
            BackupPlan.beyondKept(names, "abc123"),
        )
    }
}
