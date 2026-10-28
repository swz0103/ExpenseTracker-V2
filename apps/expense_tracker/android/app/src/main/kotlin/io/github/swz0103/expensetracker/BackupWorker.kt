package io.github.swz0103.expensetracker

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Delivers the backup the app left in `outbox/` when it was last left
 * (lib/src/features/backup/model/outbox.dart) to the phone's folder and
 * Google Drive, when one is due by the chosen rhythm, without the app
 * being opened. The backup is already encrypted: this job never has the
 * ledger's key. It reads the settings from preferences.json, which only
 * the app writes, and notes what it delivered, and what went wrong, in
 * `outbox/delivered.json`, which the app reads when next opened.
 *
 * WorkManager runs it about every six hours while the battery is not low,
 * and again after a restart. Drive is only sent to on Wi-Fi or another
 * network that costs nothing per byte, as the app does.
 */
class BackupWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        try {
            deliver()
        } catch (e: Exception) {
            // Tried again at the next run.
        }
        return Result.success()
    }

    private fun read(file: File): JSONObject? = try {
        if (file.exists()) JSONObject(file.readText()) else null
    } catch (e: Exception) {
        null
    }

    private fun deliver() {
        val files = applicationContext.filesDir
        val outbox = File(files, "outbox")
        val preferences = read(File(files, "preferences.json")) ?: return
        val ready = read(File(outbox, "ready.json")) ?: return
        val backup = File(outbox, ready.optString("file"))
        if (ready.optString("file").isEmpty() || !backup.exists()) return
        val revision = ready.getInt("revision")
        val ledger = ready.getString("ledger")
        val mark = ready.optString("mark")
        val delivered = read(File(outbox, "delivered.json")) ?: JSONObject()
        val problems = delivered.optJSONObject("problems") ?: JSONObject()
        val now = System.currentTimeMillis()

        // The last delivery of this ledger the app or this job made there.
        fun last(place: String, at: String, revisionKey: String, uri: String?): Pair<Long?, Int?> {
            var time = BackupPlan.millisOf(preferences.optString(at).ifEmpty { null })
            var made = if (preferences.has(revisionKey) && !preferences.isNull(revisionKey)) {
                preferences.getInt(revisionKey)
            } else {
                null
            }
            val here = delivered.optJSONObject(place)
            if (here != null && here.optString("ledger") == ledger &&
                (uri == null || here.optString("uri") == uri)
            ) {
                val hereAt = here.getLong("at")
                if (time == null || hereAt > time) {
                    time = hereAt
                    made = here.getInt("revision")
                }
            }
            return time to made
        }

        var phoneHas = true
        val folder = preferences.optString("phoneFolder").ifEmpty { null }
        if (folder != null && !preferences.isNull("phoneFolder")) {
            val (at, made) = last("phone", "phoneBackedUp", "phoneRevision", folder)
            val every = if (preferences.optBoolean("phoneDaily")) BackupPlan.DAY else 7 * BackupPlan.DAY
            if (BackupPlan.due(now, at, made, revision, every)) {
                try {
                    toFolder(Uri.parse(folder), backup, mark, ready.optLong("at", now))
                    delivered.put("phone", entry(now, revision, ledger).put("uri", folder))
                    problems.remove("phone")
                } catch (e: Exception) {
                    phoneHas = false
                    problems.put("phone", problem(now, e))
                }
            } else {
                phoneHas = made == revision
            }
        }

        var driveHas = true
        if (preferences.optBoolean("driveLinked")) {
            val (at, made) = last("drive", "driveBackedUp", "driveRevision", null)
            if (!BackupPlan.due(now, at, made, revision, 7 * BackupPlan.DAY)) {
                driveHas = made == revision
            } else if (!unmetered()) {
                driveHas = false
            } else {
                try {
                    DriveUploader(applicationContext).upload(backup, ledger)
                    delivered.put("drive", entry(now, revision, ledger))
                    problems.remove("drive")
                } catch (e: Exception) {
                    driveHas = false
                    problems.put("drive", problem(now, e))
                }
            }
        }

        delivered.put("problems", problems)
        save(File(outbox, "delivered.json"), delivered.toString())
        // Every place holds it: the copy here is no longer needed.
        if (phoneHas && driveHas) backup.delete()
    }

    private fun entry(at: Long, revision: Int, ledger: String) =
        JSONObject().put("at", at).put("revision", revision).put("ledger", ledger)

    private fun problem(at: Long, e: Exception) =
        JSONObject().put("at", at).put("message", e.message ?: e.javaClass.simpleName)

    /** Writes the backup into the folder and keeps the newest of this ledger. */
    private fun toFolder(tree: Uri, backup: File, mark: String, at: Long) {
        val resolver = applicationContext.contentResolver
        if (!FolderFiles.allowed(resolver, tree)) {
            throw IllegalStateException("沒有這個資料夾的存取權，請重新選擇")
        }
        FolderFiles.write(resolver, tree, backup, BackupPlan.phoneName(mark, at))
        val listed = FolderFiles.list(resolver, tree)
        val old = BackupPlan.beyondKept(listed.map { it["name"] as String }, mark).toSet()
        for (file in listed) {
            if ((file["name"] as String) in old) FolderFiles.delete(resolver, tree, file["id"] as String)
        }
    }

    private fun unmetered(): Boolean {
        val manager =
            applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }

    /** Written beside, then renamed over: the app never reads half a file. */
    private fun save(file: File, text: String) {
        val next = File(file.parentFile, "${file.name}.${System.nanoTime()}.new")
        next.writeText(text)
        if (!next.renameTo(file)) next.delete()
    }

    companion object {
        private const val NAME = "backups"

        /** Runs the job about every six hours from now on, or stops it. */
        fun schedule(context: Context, on: Boolean) {
            val work = WorkManager.getInstance(context)
            if (!on) {
                work.cancelUniqueWork(NAME)
                return
            }
            val request = PeriodicWorkRequest.Builder(BackupWorker::class.java, 6, TimeUnit.HOURS)
                .setConstraints(Constraints.Builder().setRequiresBatteryNotLow(true).build())
                .build()
            work.enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }
    }
}
