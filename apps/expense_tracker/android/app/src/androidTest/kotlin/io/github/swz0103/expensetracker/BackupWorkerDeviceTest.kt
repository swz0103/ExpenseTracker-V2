package io.github.swz0103.expensetracker

import android.content.Context
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.ListenableWorker
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.testing.TestWorkerBuilder
import androidx.work.testing.WorkManagerTestInitHelper
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.Executors

/**
 * The background backup (BackupWorker.kt) on the phone itself: a folder
 * the app may no longer write to is noted for the app to say, and the
 * backup waiting in the outbox is kept for the next try; turning the
 * backups on leaves a job with WorkManager. It reads the settings the app
 * hands it (background.json), the folder sealed.
 */
@RunWith(AndroidJUnit4::class)
class BackupWorkerDeviceTest {
    private val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
    private val files = context.filesDir
    private val outbox = File(files, "outbox")
    private val settings = File(files, "background.json")
    private var keptSettings: String? = null

    @Before
    fun setUp() {
        keptSettings = if (settings.exists()) settings.readText() else null
        outbox.deleteRecursively()
        outbox.mkdirs()
    }

    @After
    fun tearDown() {
        outbox.deleteRecursively()
        val kept = keptSettings
        if (kept != null) settings.writeText(kept) else settings.delete()
    }

    /** The rules as the app hands them over (BackupRules.handover). */
    private val plan = JSONObject()
        .put("keep", 5)
        .put("daily", 86_400_000L)
        .put("weekly", 604_800_000L)
        .put("drive", 86_400_000L)
        .put("phoneName", "記帳本-abc123-20261028-1104.etbk")
        .put("phonePrefix", "記帳本-abc123-")
        .put("suffix", ".etbk")
        .put("driveFolder", "記帳本備份")

    /**
     * The settings as the app hands them over (Preferences.backgroundPlan):
     * a phone folder, sealed for the job, daily, never backed up; Drive
     * not linked. [sealed] in place of the folder sealed.
     */
    private fun handFolder(sealed: String? = null) {
        val folder = "content://com.android.externalstorage.documents/tree/primary%3ABackups"
        val blob = sealed ?: Base64.encodeToString(
            QuickSeal.seal(folder.toByteArray(Charsets.UTF_8), QuickSeal.FOLDER_CONTEXT.toByteArray(Charsets.UTF_8)),
            Base64.NO_WRAP,
        )
        settings.writeText(
            JSONObject()
                .put("v", 1)
                .put("updateChecks", true)
                .put("drive", JSONObject.NULL)
                .put(
                    "phone",
                    JSONObject()
                        .put("folder", blob)
                        .put("id", "folder-1")
                        .put("daily", true)
                        .put("at", JSONObject.NULL)
                        .put("revision", JSONObject.NULL),
                )
                .toString(),
        )
    }

    @Test
    fun aFolderNoLongerAllowedIsNotedAndTheBackupKept() {
        handFolder()
        val backup = File(outbox, "ready.etbk").apply { writeText("sealed") }
        File(outbox, "ready.json").writeText(
            JSONObject()
                .put("file", backup.name)
                .put("revision", 3)
                .put("ledger", "L1")
                .put("mark", "abc123")
                .put("plan", plan)
                .toString(),
        )
        val worker = TestWorkerBuilder.from(context, BackupWorker::class.java, Executors.newSingleThreadExecutor())
            .build()
        assertTrue(worker.doWork() is ListenableWorker.Result.Success)

        val delivered = JSONObject(File(outbox, "delivered.json").readText())
        val problem = delivered.getJSONObject("problems").getJSONObject("phone")
        assertEquals("FolderDenied", problem.getString("message"))
        assertTrue("kept for the next try", backup.exists())
        // Only the folder's id is written down, never the folder.
        assertTrue(!File(outbox, "delivered.json").readText().contains("content://"))
    }

    @Test
    fun aFolderThatNoLongerOpensIsAFolderToChooseAgain() {
        // PRIV-1: sealed by a key the phone no longer has, or damaged.
        handFolder(sealed = Base64.encodeToString(ByteArray(40), Base64.NO_WRAP))
        val backup = File(outbox, "ready.etbk").apply { writeText("sealed") }
        File(outbox, "ready.json").writeText(
            JSONObject()
                .put("file", backup.name)
                .put("revision", 3)
                .put("ledger", "L1")
                .put("mark", "abc123")
                .put("plan", plan)
                .toString(),
        )
        val worker = TestWorkerBuilder.from(context, BackupWorker::class.java, Executors.newSingleThreadExecutor())
            .build()
        assertTrue(worker.doWork() is ListenableWorker.Result.Success)
        val problem = JSONObject(File(outbox, "delivered.json").readText())
            .getJSONObject("problems").getJSONObject("phone")
        assertEquals("FolderDenied", problem.getString("message"))
        assertTrue("kept for the next try", backup.exists())
    }

    @Test
    fun aBackupHandedOverWithoutTheAppsRulesWaitsForTheApp() {
        // Written by a version before the rules were handed over: the
        // app hands them over when next opened (Outbox.prepare).
        handFolder()
        val backup = File(outbox, "ready.etbk").apply { writeText("sealed") }
        File(outbox, "ready.json").writeText(
            JSONObject().put("file", backup.name).put("revision", 3).put("ledger", "L1").toString(),
        )
        val worker = TestWorkerBuilder.from(context, BackupWorker::class.java, Executors.newSingleThreadExecutor())
            .build()
        assertTrue(worker.doWork() is ListenableWorker.Result.Success)
        assertTrue("nothing noted", !File(outbox, "delivered.json").exists())
        assertTrue("kept", backup.exists())
    }

    @Test
    fun aRunWithNothingToDeliverLeavesWhatWasNotedAsItWas() {
        // Review 28 finding 4: no folder and Drive unlinked, the usual
        // run; what was noted is not written again.
        settings.writeText(JSONObject().put("v", 1).put("drive", JSONObject.NULL).put("phone", JSONObject.NULL).toString())
        val backup = File(outbox, "ready.etbk").apply { writeText("sealed") }
        File(outbox, "ready.json").writeText(
            JSONObject()
                .put("file", backup.name)
                .put("revision", 3)
                .put("ledger", "L1")
                .put("mark", "abc123")
                .put("plan", plan)
                .toString(),
        )
        // Spaced as JSONObject never writes it: a write would change it.
        val noted = "{ \"problems\" : { } }"
        val delivered = File(outbox, "delivered.json").apply { writeText(noted) }
        val worker = TestWorkerBuilder.from(context, BackupWorker::class.java, Executors.newSingleThreadExecutor())
            .build()
        assertTrue(worker.doWork() is ListenableWorker.Result.Success)
        assertEquals(noted, delivered.readText())
    }

    @Test
    fun aRunWhileAnotherIsUnderWayLeavesTheOutboxAlone() {
        // Review 21 finding 2: a stopped run still finishing, and the next.
        handFolder()
        val backup = File(outbox, "ready.etbk").apply { writeText("sealed") }
        File(outbox, "ready.json").writeText(
            JSONObject()
                .put("file", backup.name)
                .put("revision", 3)
                .put("ledger", "L1")
                .put("mark", "abc123")
                .put("plan", plan)
                .toString(),
        )
        val worker = TestWorkerBuilder.from(context, BackupWorker::class.java, Executors.newSingleThreadExecutor())
            .build()
        val second = BackupWorker.RUNS.run(whenBusy = null as ListenableWorker.Result?) { worker.doWork() }
        assertTrue(second is ListenableWorker.Result.Retry)
        assertTrue("nothing noted", !File(outbox, "delivered.json").exists())
        assertTrue("kept", backup.exists())
    }

    @Test
    fun turningTheBackupsOnLeavesAJob() {
        WorkManagerTestInitHelper.initializeTestWorkManager(context)
        BackupWorker.schedule(context, on = true)
        val work = WorkManager.getInstance(context).getWorkInfosForUniqueWork("backups").get()
        assertEquals(WorkInfo.State.ENQUEUED, work.single().state)
        BackupWorker.schedule(context, on = false)
        val after = WorkManager.getInstance(context).getWorkInfosForUniqueWork("backups").get()
        assertTrue(after.all { it.state == WorkInfo.State.CANCELLED })
    }
}
