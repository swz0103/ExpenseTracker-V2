package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException
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

    /** Runs [places] in turn, [noted] written down into [kept]. */
    private fun inTurn(
        places: List<() -> Unit>,
        noted: Map<String, Int>,
        kept: MutableList<String>,
        written: String? = null,
        write: (String) -> Unit = { kept.add(it) },
    ) = BackupPlan.inTurn(places, { noted.toSortedMap().toString() }, written, write)

    @Test
    fun aStopDuringTheSecondPlaceKeepsWhatTheFirstReceived() {
        // Review 26 finding 2: the folder copy is noted, then the Drive
        // upload is stopped between two parts.
        val noted = mutableMapOf<String, Int>()
        val kept = mutableListOf<String>()
        try {
            inTurn(
                listOf(
                    { noted["phone"] = 3 },
                    { throw BackgroundWork.Stopped() },
                ),
                noted,
                kept,
            )
            fail("the stop goes on to the worker")
        } catch (e: BackgroundWork.Stopped) {
            // Expected: the run ends where it is.
        }
        // Written once, after the folder: nothing changed after it.
        assertEquals(listOf("{phone=3}"), kept)
    }

    @Test
    fun aRunThatEndsWellWritesEachChangeOnce() {
        val noted = mutableMapOf<String, Int>()
        val kept = mutableListOf<String>()
        inTurn(listOf({ noted["phone"] = 3 }, { noted["drive"] = 3 }), noted, kept)
        assertEquals(listOf("{phone=3}", "{drive=3, phone=3}"), kept)
    }

    @Test
    fun aRunWithNothingDueWritesNothing() {
        // Review 28 finding 4: Drive unlinked, the folder not due; the
        // file already holds what is noted.
        val noted = mapOf("phone" to 3)
        val kept = mutableListOf<String>()
        inTurn(listOf({}, {}), noted, kept, written = "{phone=3}")
        assertEquals(emptyList<String>(), kept)
    }

    @Test
    fun aRunDeliveredOnlyToTheFolderWritesOnce() {
        // Drive unlinked: the folder's copy is noted, then nothing more.
        val noted = mutableMapOf("phone" to 2)
        val kept = mutableListOf<String>()
        inTurn(listOf({ noted["phone"] = 3 }, {}), noted, kept, written = "{phone=2}")
        assertEquals(listOf("{phone=3}"), kept)
    }

    @Test
    fun aStopInTheFirstPlaceStillKeepsWhatWasNotedBefore() {
        val noted = mutableMapOf<String, Int>()
        val kept = mutableListOf<String>()
        try {
            inTurn(
                listOf(
                    {
                        noted["problem"] = 1
                        throw BackgroundWork.Stopped()
                    },
                    { kept.add("drive ran") },
                ),
                noted,
                kept,
            )
            fail("the stop goes on to the worker")
        } catch (e: BackgroundWork.Stopped) {
            // Expected.
        }
        assertEquals(listOf("{problem=1}"), kept)
    }

    @Test
    fun aStopIsNotReplacedByAFailureToWriteDown() {
        // Review 28 finding 4: the Drive stage is stopped, and writing
        // down then fails as the storage is full.
        val noted = mutableMapOf<String, Int>()
        val full = IOException("No space left on device")
        try {
            inTurn(
                listOf(
                    { noted["phone"] = 3 },
                    {
                        noted["drive"] = 1
                        throw BackgroundWork.Stopped()
                    },
                ),
                noted,
                mutableListOf(),
                write = { if (it.contains("drive")) throw full },
            )
            fail("the stop goes on to the worker")
        } catch (e: BackgroundWork.Stopped) {
            assertEquals(listOf<Throwable>(full), e.suppressed.toList())
        }
    }

    @Test
    fun aStopInTheFirstPlaceIsNotReplacedEither() {
        val full = IOException("No space left on device")
        try {
            inTurn(
                listOf({ throw BackgroundWork.Stopped() }, {}),
                mapOf("phone" to 3),
                mutableListOf(),
                write = { throw full },
            )
            fail("the stop goes on to the worker")
        } catch (e: BackgroundWork.Stopped) {
            assertEquals(listOf<Throwable>(full), e.suppressed.toList())
        }
    }

    @Test
    fun aFailureToWriteDownAfterARunThatWentWellIsThrown() {
        val full = IOException("No space left on device")
        try {
            inTurn(listOf({}, {}), mapOf("phone" to 3), mutableListOf(), write = { throw full })
            fail("the failure goes on to the worker")
        } catch (e: IOException) {
            assertEquals(full, e)
        }
    }
}
