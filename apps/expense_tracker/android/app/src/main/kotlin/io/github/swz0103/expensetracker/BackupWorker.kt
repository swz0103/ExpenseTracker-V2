package io.github.swz0103.expensetracker

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.io.File

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
 * and again after a restart; with Drive linked, only once there is a
 * network ([BackgroundWork]). Drive gets a backup a day when the ledger
 * changed: the ledger alone on any network, or, with the receipt photos,
 * only on Wi-Fi or another network that costs nothing per byte while the
 * person keeps `photosOnWifi` on, as the app does. An upload cut short
 * goes on from where it stopped at the next run ([DriveUploader]); a run
 * the network cut short is tried again after a growing wait, and only
 * after [BackgroundWork.RETRIES] of them is it noted as failed (AND-05).
 * The upload goes in parts; a run WorkManager stops ends between two, or
 * in the folder copy, and is run again later, having written down only
 * what the places before received (a folder copy made before a stop in
 * the Drive upload is not made again); and only
 * one run works at a time, so a stopped one still finishing and the next
 * never share an upload or the outbox.
 */
class BackupWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result = RUNS.run(whenBusy = Result.retry()) {
        try {
            if (deliver()) Result.retry() else Result.success()
        } catch (e: BackgroundWork.Stopped) {
            Result.retry()
        } catch (e: InterruptedException) {
            // Whoever interrupted the thread still learns of it.
            Thread.currentThread().interrupt()
            Result.retry()
        } catch (e: Exception) {
            // Tried again at the next run.
            Result.success()
        }
    }

    /** Ends the run where it is when WorkManager stopped it. */
    private fun stopIfAsked() {
        if (isStopped) throw BackgroundWork.Stopped()
    }

    /** A stop or an interruption ends the run; it is no failure of a place. */
    private fun passOn(e: Exception) {
        if (e is BackgroundWork.Stopped || e is InterruptedException) throw e
    }

    private fun read(file: File): JSONObject? = try {
        if (file.exists()) JSONObject(file.readText()) else null
    } catch (e: Exception) {
        null
    }

    /** Delivers what is due; true when a delivery the network cut short is to be tried again soon. */
    private fun deliver(): Boolean {
        val files = applicationContext.filesDir
        val outbox = File(files, "outbox")
        val preferences = read(File(files, "preferences.json")) ?: return false
        val ready = read(File(outbox, "ready.json")) ?: return false
        val backup = File(outbox, ready.optString("file"))
        if (ready.optString("file").isEmpty() || !backup.exists()) return false
        // Drive's own copy without the photos, when the folder takes them.
        val driveBackup = ready.optString("driveFile").ifEmpty { null }
            ?.let { File(outbox, it) }?.takeIf { it.exists() } ?: backup
        val photos = ready.optBoolean("drivePhotos", true)
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
        var driveHas = true
        var again = false
        val folder = preferences.optString("phoneFolder").ifEmpty { null }
        fun toPhone() {
            if (folder == null || preferences.isNull("phoneFolder")) return
            val (at, made) = last("phone", "phoneBackedUp", "phoneRevision", folder)
            val every = if (preferences.optBoolean("phoneDaily")) BackupPlan.DAY else 7 * BackupPlan.DAY
            if (BackupPlan.due(now, at, made, revision, every)) {
                stopIfAsked()
                try {
                    toFolder(Uri.parse(folder), backup, mark, ready.optLong("at", now))
                    delivered.put("phone", entry(now, revision, ledger).put("uri", folder))
                    problems.remove("phone")
                } catch (e: Exception) {
                    passOn(e)
                    phoneHas = false
                    problems.put("phone", problem(now, e))
                }
            } else {
                phoneHas = made == revision
            }
        }

        fun toDrive() {
            if (!preferences.optBoolean("driveLinked")) return
            val (at, made) = last("drive", "driveBackedUp", "driveRevision", null)
            // The same key as Preferences.photosOnWifiKey; on unless turned off.
            val onWifi = preferences.optBoolean("photosOnWifi", true)
            if (!BackupPlan.due(now, at, made, revision, BackupPlan.DAY)) {
                driveHas = made == revision
            } else if (photos && onWifi && !unmetered()) {
                driveHas = false
            } else {
                stopIfAsked()
                try {
                    DriveUploader(applicationContext) { isStopped }
                        .upload(driveBackup, ledger, UploadSession.In(File(outbox, UploadSession.FILE)))
                    delivered.put("drive", entry(now, revision, ledger))
                    problems.remove("drive")
                } catch (e: Exception) {
                    passOn(e)
                    driveHas = false
                    if (BackgroundWork.retries(e, runAttemptCount)) {
                        again = true
                    } else {
                        problems.put("drive", problem(now, e))
                    }
                }
            }
        }

        // What each place received is written down before the next, and
        // however the run ends: a stop during the Drive upload keeps that
        // the folder already has this backup.
        BackupPlan.inTurn(listOf(::toPhone, ::toDrive)) {
            delivered.put("problems", problems)
            save(File(outbox, "delivered.json"), delivered.toString())
        }
        // Every place holds it: the copy here is no longer needed.
        if (phoneHas && driveHas) {
            backup.delete()
            driveBackup.delete()
        }
        return again
    }

    private fun entry(at: Long, revision: Int, ledger: String) =
        JSONObject().put("at", at).put("revision", revision).put("ledger", ledger)

    /** What went wrong, as the app's error log shows it: under Play services' wrapping. */
    private fun problem(at: Long, e: Exception): JSONObject {
        val cause = BackgroundWork.causeOf(e)
        return JSONObject().put("at", at).put("message", cause.message ?: cause.javaClass.simpleName)
    }

    /** Writes the backup into the folder and keeps the newest of this ledger. */
    private fun toFolder(tree: Uri, backup: File, mark: String, at: Long) {
        val resolver = applicationContext.contentResolver
        if (!FolderFiles.allowed(resolver, tree)) {
            throw IllegalStateException("沒有這個資料夾的存取權，請重新選擇")
        }
        FolderFiles.write(resolver, tree, backup, BackupPlan.phoneName(mark, at)) { isStopped }
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

        /** One run at a time in this process. */
        internal val RUNS = BackgroundWork.OneAtATime()

        /**
         * Runs the job about every six hours from now on, or stops it; with
         * Drive linked (as preferences.json says), only once there is a
         * network.
         */
        fun schedule(context: Context, on: Boolean) {
            val work = WorkManager.getInstance(context)
            if (!on) {
                work.cancelUniqueWork(NAME)
                return
            }
            val drive = try {
                JSONObject(File(context.filesDir, "preferences.json").readText()).optBoolean("driveLinked")
            } catch (e: Exception) {
                // Unread: the network is asked for, as Drive may need it.
                true
            }
            val request = BackgroundWork.periodic(BackupWorker::class.java, 6, BackgroundWork.backupNetwork(drive))
            // UPDATE: Drive linked or unlinked since changes what it waits
            // for, keeping its place in time.
            work.enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
        }
    }
}
