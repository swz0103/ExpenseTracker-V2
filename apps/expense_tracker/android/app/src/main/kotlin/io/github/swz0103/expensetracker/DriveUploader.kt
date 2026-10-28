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
 * newest five of that ledger kept and older ones moved to the Drive trash.
 * It never shows Google's screens: without access already given, it does
 * nothing.
 */
internal class DriveUploader(private val context: Context) {
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

    private class Response(val status: Int, val location: String?, val body: String)

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
    ): Response {
        for (attempt in 0..1) {
            val bearer = access() ?: throw NotAllowed()
            val connection = URL(url).openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 20_000
                connection.readTimeout = 300_000
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
                        connection.setFixedLengthStreamingMode(file.length())
                        connection.outputStream.use { out -> file.inputStream().use { it.copyTo(out) } }
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
                if (status !in 200..299) throw Refused(status, "$status ${reason(body)}")
                return Response(status, connection.getHeaderField("Location"), body)
            } finally {
                connection.disconnect()
            }
        }
        throw NotAllowed()
    }

    class NotAllowed : IOException("Google Drive access was not given.")

    private fun reason(body: String): String = try {
        JSONObject(body).optJSONObject("error")?.optString("message") ?: ""
    } catch (e: Exception) {
        ""
    }

    private fun encode(text: String) = URLEncoder.encode(text, "UTF-8")

    private fun quote(text: String) = text.replace("\\", "\\\\").replace("'", "\\'")

    /** The folder's id, made when there is none. */
    private fun folder(): String {
        val query = "name='${quote(FOLDER)}' and mimeType='$FOLDER_TYPE' and trashed=false"
        val found = send("GET", "$API?q=${encode(query)}&fields=${encode("files(id)")}&spaces=drive")
        val files = JSONObject(found.body).optJSONArray("files") ?: JSONArray()
        if (files.length() > 0) return files.getJSONObject(0).getString("id")
        val made = send(
            "POST",
            "$API?fields=id",
            mapOf("Content-Type" to "application/json; charset=utf-8"),
            JSONObject().put("name", FOLDER).put("mimeType", FOLDER_TYPE).toString(),
        )
        return JSONObject(made.body).getString("id")
    }

    /**
     * Uploads [file] into the folder marked as a backup of [ledger], then
     * moves that ledger's backups beyond the newest [BackupPlan.KEEP] to
     * the Drive trash; pruning is best effort.
     */
    fun upload(file: File, ledger: String) {
        val parent = folder()
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
        send("PUT", location, mapOf("Content-Type" to "application/octet-stream"), file = file)
        try {
            prune(parent, ledger)
        } catch (e: IOException) {
            // Tried again after the next upload.
        }
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
            .filter { it.optString("name").endsWith(".etbk") }
            .sortedByDescending { it.optString("modifiedTime") }
        for (old in ours.drop(BackupPlan.KEEP)) {
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

    private companion object {
        const val DRIVE_SCOPE = "https://www.googleapis.com/auth/drive.file"
        const val FOLDER = "記帳本備份"
        const val FOLDER_TYPE = "application/vnd.google-apps.folder"
        const val API = "https://www.googleapis.com/drive/v3/files"
        const val UPLOAD = "https://www.googleapis.com/upload/drive/v3/files"
    }
}
