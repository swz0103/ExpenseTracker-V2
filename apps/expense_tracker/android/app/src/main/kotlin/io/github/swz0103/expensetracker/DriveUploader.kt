package io.github.swz0103.expensetracker

import android.content.Context
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.ClearTokenRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import com.google.android.gms.tasks.Tasks
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

/**
 * Uploads a backup to the folder 記帳本備份 on Google Drive from the
 * background job (BackupWorker.kt), as DriveBackup.upload does in the app
 * (drive_backup.dart): the same folder, the same mark of the ledger, the
 * newest the app keeps of that ledger kept and older ones moved to the
 * Drive trash, all as the app hands them over ([BackupPlan.Handed]).
 * It never shows Google's screens: without access already given, it does
 * nothing.
 */
internal class DriveUploader(
    private val context: Context,
    /** The app's rules: the folder's name, how many stay, the names' end. */
    private val plan: BackupPlan.Handed,
    /** Whether WorkManager stopped the run: checked before each part of an upload. */
    private val stopped: () -> Boolean = { false },
) {
    class Refused(val status: Int, message: String) : IOException(message)

    private var token: String? = null

    /** An access token already granted for `drive.file`; null when Google would ask. */
    private fun access(): String? {
        token?.let { return it }
        val request = AuthorizationRequest.builder()
            .setRequestedScopes(listOf(Scope(DRIVE_SCOPE)))
            .build()
        val granted = Tasks.await(
            Identity.getAuthorizationClient(context).authorize(request),
            60,
            TimeUnit.SECONDS,
        )
        if (granted.hasResolution()) return null
        token = granted.accessToken
        return token
    }

    private class Response(val status: Int, val location: String?, val range: String?, val body: String)

    /**
     * Sends a request with the access token; once more with a fresh token
     * when Google says the old one ran out.
     */
    private fun send(
        method: String,
        url: String,
        headers: Map<String, String> = emptyMap(),
        text: String? = null,
        file: File? = null,
        from: Long = 0,
        length: Long = 0,
        also: Set<Int> = emptySet(),
    ): Response {
        for (attempt in 0..1) {
            val bearer = access() ?: throw NotAllowed()
            val connection = URL(url).openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 20_000
                connection.readTimeout = 300_000
                // A redirect would carry the token and the backup on to
                // wherever it points: none is followed.
                connection.instanceFollowRedirects = false
                // HttpURLConnection has no PATCH; Google takes the override.
                if (method == "PATCH") {
                    connection.requestMethod = "POST"
                    connection.setRequestProperty("X-HTTP-Method-Override", "PATCH")
                } else {
                    connection.requestMethod = method
                }
                connection.setRequestProperty("Authorization", "Bearer $bearer")
                headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
                when {
                    file != null -> {
                        connection.doOutput = true
                        connection.setFixedLengthStreamingMode(length)
                        connection.outputStream.use { out ->
                            file.inputStream().use { input ->
                                ResumableUpload.skip(input, from)
                                ResumableUpload.copy(input, out, length)
                            }
                        }
                    }
                    method == "PUT" -> {
                        // A status query of an upload: no body.
                        connection.doOutput = true
                        connection.setFixedLengthStreamingMode(0)
                        connection.outputStream.close()
                    }
                    text != null -> {
                        val bytes = text.toByteArray(Charsets.UTF_8)
                        connection.doOutput = true
                        connection.setFixedLengthStreamingMode(bytes.size)
                        connection.outputStream.use { it.write(bytes) }
                    }
                }
                val status = connection.responseCode
                val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                val body = stream?.use { it.readBytes().toString(Charsets.UTF_8) } ?: ""
                if (status == 401 && attempt == 0) {
                    token = null
                    Tasks.await(
                        Identity.getAuthorizationClient(context)
                            .clearToken(ClearTokenRequest.builder().setToken(bearer).build()),
                        30,
                        TimeUnit.SECONDS,
                    )
                    continue
                }
                // Drive's own sentence can name the account or a file: the
                // status alone goes on (review 33).
                if (status !in 200..299 && status !in also) throw Refused(status, "HTTP $status")
                return Response(
                    status,
                    connection.getHeaderField("Location"),
                    connection.getHeaderField("Range"),
                    body,
                )
            } finally {
                connection.disconnect()
            }
        }
        throw NotAllowed()
    }

    class NotAllowed : IOException("Google Drive access was not given.")

    private fun encode(text: String) = URLEncoder.encode(text, "UTF-8")

    private fun quote(text: String) = text.replace("\\", "\\\\").replace("'", "\\'")

    /** The folder's id, made when there is none. */
    private fun folder(): String {
        val query = "name='${quote(plan.driveFolder)}' and mimeType='$FOLDER_TYPE' and trashed=false"
        val found = send("GET", "$API?q=${encode(query)}&fields=${encode("files(id)")}&spaces=drive")
        val files = JSONObject(found.body).optJSONArray("files") ?: JSONArray()
        if (files.length() > 0) return files.getJSONObject(0).getString("id")
        val made = send(
            "POST",
            "$API?fields=id",
            mapOf("Content-Type" to "application/json; charset=utf-8"),
            JSONObject().put("name", plan.driveFolder).put("mimeType", FOLDER_TYPE).toString(),
        )
        return JSONObject(made.body).getString("id")
    }

    /**
     * Uploads [file] into the folder marked as a backup of [ledger], then
     * moves that ledger's backups beyond the newest [BackupPlan.Handed.keep] to
     * the Drive trash; pruning is best effort. An upload cut short is kept
     * in [sessions] and goes on from where Drive says it stopped the next
     * time the same file is uploaded, rather than from the start (AND-05).
     */
    fun upload(file: File, ledger: String, sessions: UploadSession.Store) {
        val parent = folder()
        val size = file.length()
        var location: String? = null
        var from = 0L
        val saved = sessions.read()?.takeIf { it.fits(file) && isGoogleUpload(it.location) }
        if (saved != null) {
            // Asks how much Drive has: 308 with the bytes it holds, or 2xx
            // when it has it all; an upload it no longer knows starts anew.
            val asked = try {
                send(
                    "PUT",
                    saved.location,
                    mapOf("Content-Range" to ResumableUpload.query(size)),
                    also = setOf(ResumableUpload.INCOMPLETE),
                )
            } catch (e: Refused) {
                if (e.status != 404 && e.status != 410) throw e
                null
            }
            when (asked?.status) {
                null -> sessions.clear()
                ResumableUpload.INCOMPLETE -> {
                    location = saved.location
                    from = ResumableUpload.nextByte(asked.range)
                }
                else -> {
                    sessions.clear()
                    prune(parent, ledger)
                    return
                }
            }
        }
        if (stopped()) throw BackgroundWork.Stopped()
        val target = location ?: start(file, ledger, parent).also {
            sessions.write(UploadSession(it, file.name, size))
        }
        // In parts, each a request of its own, so a run WorkManager stops
        // ends between two; the next goes on from what Drive holds.
        ResumableUpload.inParts(from, size, stopped) { first, last ->
            val answer = send(
                "PUT",
                target,
                mapOf(
                    "Content-Type" to "application/octet-stream",
                    "Content-Range" to ResumableUpload.part(first, last, size),
                ),
                file = file,
                from = first,
                length = last - first + 1,
                also = setOf(ResumableUpload.INCOMPLETE),
            )
            if (answer.status == ResumableUpload.INCOMPLETE) ResumableUpload.nextByte(answer.range) else null
        }
        sessions.clear()
        try {
            prune(parent, ledger)
        } catch (e: IOException) {
            // Tried again after the next upload.
        }
    }

    /** Asks Drive for an upload address of [file] into [parent]. */
    private fun start(file: File, ledger: String, parent: String): String {
        val start = send(
            "POST",
            "$UPLOAD?uploadType=resumable&fields=id",
            mapOf(
                "Content-Type" to "application/json; charset=utf-8",
                "X-Upload-Content-Type" to "application/octet-stream",
                "X-Upload-Content-Length" to file.length().toString(),
            ),
            JSONObject()
                .put("name", file.name)
                .put("parents", JSONArray().put(parent))
                .put("mimeType", "application/octet-stream")
                .put("appProperties", JSONObject().put("ledger", ledger))
                .toString(),
        )
        val location = start.location ?: throw Refused(0, "no upload address")
        // The backup and the token go only to Google's own upload host.
        if (!isGoogleUpload(location)) throw Refused(0, "upload address")
        return location
    }

    private fun prune(parent: String, ledger: String) {
        val query = "'${quote(parent)}' in parents and trashed=false and " +
            "appProperties has { key='ledger' and value='${quote(ledger)}' }"
        val listed = send(
            "GET",
            "$API?q=${encode(query)}&fields=${encode("files(id,name,modifiedTime)")}" +
                "&orderBy=${encode("modifiedTime desc")}&pageSize=100&spaces=drive",
        )
        val files = JSONObject(listed.body).optJSONArray("files") ?: JSONArray()
        val ours = (0 until files.length())
            .map { files.getJSONObject(it) }
            .filter { it.optString("name").endsWith(plan.suffix) }
            .sortedByDescending { it.optString("modifiedTime") }
        for (old in ours.drop(plan.keep)) {
            try {
                send(
                    "PATCH",
                    "$API/${encode(old.getString("id"))}?fields=id",
                    mapOf("Content-Type" to "application/json; charset=utf-8"),
                    "{\"trashed\":true}",
                )
            } catch (e: Refused) {
                if (e.status != 404) throw e
            }
        }
    }

    internal companion object {
        /** Whether [location] is Google's own upload address, over HTTPS. */
        fun isGoogleUpload(location: String): Boolean {
            val uri = try {
                java.net.URI(location)
            } catch (e: Exception) {
                return false
            }
            val host = uri.host?.lowercase() ?: return false
            return uri.scheme == "https" &&
                (host == "googleapis.com" || host.endsWith(".googleapis.com"))
        }

        private const val DRIVE_SCOPE = "https://www.googleapis.com/auth/drive.file"
        private const val FOLDER_TYPE = "application/vnd.google-apps.folder"
        private const val API = "https://www.googleapis.com/drive/v3/files"
        private const val UPLOAD = "https://www.googleapis.com/upload/drive/v3/files"
    }
}
