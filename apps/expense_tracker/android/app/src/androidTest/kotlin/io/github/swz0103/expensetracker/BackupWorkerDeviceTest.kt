package io.github.swz0103.expensetracker

import android.content.Context
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
 * backups on leaves a job with WorkManager.
 */
@RunWith(AndroidJUnit4::class)
class BackupWorkerDeviceTest {
    private val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
    private val files = context.filesDir
    private val outbox = File(files, "outbox")
    private val preferences = File(files, "preferences.json")
    private var keptPreferences: String? = null

    @Before
    fun setUp() {
        keptPreferences = if (preferences.exists()) preferences.readText() else null
        outbox.deleteRecursively()
        outbox.mkdirs()
    }

    @After
    fun tearDown() {
        outbox.deleteRecursively()
        val kept = keptPreferences
        if (kept != null) preferences.writeText(kept) else preferences.delete()
    }

    @Test
    fun aFolderNoLongerAllowedIsNotedAndTheBackupKept() {
        preferences.writeText(
            JSONObject()
                .put("phoneFolder", "content://com.android.externalstorage.documents/tree/primary%3ABackups")
                .put("phoneDaily", true)
                .toString(),
        )
        val backup = File(outbox, "ready.etbk").apply { writeText("sealed") }
        File(outbox, "ready.json").writeText(
            JSONObject()
                .put("file", backup.name)
                .put("revision", 3)
                .put("ledger", "L1")
                .put("mark", "abc123")
                .toString(),
        )
        val worker = TestWorkerBuilder.from(context, BackupWorker::class.java, Executors.newSingleThreadExecutor())
            .build()
        assertTrue(worker.doWork() is ListenableWorker.Result.Success)

        val delivered = JSONObject(File(outbox, "delivered.json").readText())
        val problem = delivered.getJSONObject("problems").getJSONObject("phone")
        assertTrue(problem.getString("message"), problem.getString("message").contains("存取權"))
        assertTrue("kept for the next try", backup.exists())
    }

    @Test
    fun aRunWithNothingToDeliverLeavesWhatWasNotedAsItWas() {
        // Review 28 finding 4: no folder and Drive unlinked, the usual
        // run; what was noted is not written again.
        preferences.writeText(JSONObject().put("driveLinked", false).toString())
        val backup = File(outbox, "ready.etbk").apply { writeText("sealed") }
        File(outbox, "ready.json").writeText(
            JSONObject()
                .put("file", backup.name)
                .put("revision", 3)
                .put("ledger", "L1")
                .put("mark", "abc123")
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
        preferences.writeText(
            JSONObject()
                .put("phoneFolder", "content://com.android.externalstorage.documents/tree/primary%3ABackups")
                .put("phoneDaily", true)
                .toString(),
        )
        val backup = File(outbox, "ready.etbk").apply { writeText("sealed") }
        File(outbox, "ready.json").writeText(
            JSONObject()
                .put("file", backup.name)
                .put("revision", 3)
                .put("ledger", "L1")
                .put("mark", "abc123")
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
