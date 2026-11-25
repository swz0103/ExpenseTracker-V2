package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException

/** The background job follows the rules the app hands over (backup_rules.dart). */
class BackupPlanTest {
    private val day = 86_400_000L

    // 7 days of 86,400,000 ms.
    private val week = 604_800_000L

    // As BackupRules.handover writes it for the ledger marked abc123.
    private val plan = BackupPlan.Handed(
        keep = 5,
        daily = day,
        weekly = week,
        drive = day,
        phoneName = "記帳本-abc123-20261028-1104.etbk",
        phonePrefix = "記帳本-abc123-",
        suffix = ".etbk",
        driveFolder = "記帳本備份",
    )

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
        assertTrue(BackupPlan.due(last + day, last, 2, 3, day))
    }

    @Test
    fun thePhonesRhythmIsTheOneChosenOfThoseHandedOver() {
        assertEquals(day, plan.phoneEvery(daily = true))
        assertEquals(week, plan.phoneEvery(daily = false))
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
            BackupPlan.beyondKept(names, plan),
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

    @Test
    fun theLogIsToldTheTypeAndStatusNeverTheWords() {
        // Review 33: a server's sentence or a file's name never goes to
        // the app's error log.
        assertEquals(
            "IOException",
            BackupPlan.problemOf(IOException("/storage/emulated/0/Documents/王小明 alice@example.com")),
        )
        assertEquals("Refused HTTP 403", BackupPlan.problemOf(DriveUploader.Refused(403, "HTTP 403")))
        assertEquals("Refused", BackupPlan.problemOf(DriveUploader.Refused(0, "no upload address")))
    }

    @Test
    fun aFolderRefusingIsHandedAsItsCodeNotWords() {
        // Review 34: the app records the code; no Chinese goes through.
        assertEquals("FolderDenied", BackupPlan.problemOf(BackupPlan.FolderDenied()))
        assertEquals("IllegalStateException", BackupPlan.problemOf(IllegalStateException("沒有存取權")))
    }

    @Test
    fun aFailureWithNoNameOfItsOwnIsUnknown() {
        val anonymous = object : Exception("alice@example.com") {}
        assertEquals("Unknown", BackupPlan.problemOf(anonymous))
    }
}
