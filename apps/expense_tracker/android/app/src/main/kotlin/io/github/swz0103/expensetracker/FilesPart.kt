package io.github.swz0103.expensetracker

import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The app's private folders, and the system's save and open dialogs for
 * taking backups and files out and back in
 * (lib/src/app/android/files.dart).
 */
class FilesPart(private val activity: FragmentActivity) : ChannelPart {
    private var pendingExport: Pair<String, MethodChannel.Result>? = null
    private var pendingPick: MethodChannel.Result? = null

    /**
     * Copies a backup to where the person chooses: Downloads, Drive, ...
     * Off the main thread, as a backup with photos can be large and the
     * place a slow provider.
     */
    private val createDocument =
        activity.registerForActivityResult(
            ActivityResultContracts.CreateDocument("application/octet-stream"),
        ) { uri ->
            val (source, result) = pendingExport ?: return@registerForActivityResult
            pendingExport = null
            if (uri == null) {
                result.success(false)
                return@registerForActivityResult
            }
            Thread {
                try {
                    val output = activity.contentResolver.openOutputStream(uri)
                        ?: throw IllegalStateException("The chosen place cannot be written.")
                    output.use { File(source).inputStream().use { input -> input.copyTo(it) } }
                    activity.runOnUiThread { result.success(true) }
                } catch (e: Exception) {
                    activity.runOnUiThread { result.error("export", e.message, null) }
                }
            }.start()
        }

    /**
     * Copies the chosen file into the cache, where the app can read it; the
     * app deletes the copy once read (and at the next start, if it is
     * left). Off the main thread.
     */
    private val openDocument =
        activity.registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            val result = pendingPick ?: return@registerForActivityResult
            pendingPick = null
            if (uri == null) {
                result.success(null)
                return@registerForActivityResult
            }
            Thread {
                try {
                    val input = activity.contentResolver.openInputStream(uri)
                        ?: throw IllegalStateException("The chosen file cannot be read.")
                    val copy = File(activity.cacheDir, "restore.etbk")
                    input.use { copy.outputStream().use { output -> it.copyTo(output) } }
                    activity.runOnUiThread { result.success(copy.absolutePath) }
                } catch (e: Exception) {
                    activity.runOnUiThread { result.error("pick", e.message, null) }
                }
            }.start()
        }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "filesDir" -> result.success(activity.filesDir.absolutePath)
            "cacheDir" -> result.success(activity.cacheDir.absolutePath)
            "exportFile" -> {
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                if (pendingExport != null) {
                    result.error("busy", "A file is being saved.", null)
                } else if (path == null || name == null) {
                    result.error("bad-arguments", "path and name are required", null)
                } else {
                    pendingExport = path to result
                    launchOr(result, { pendingExport = null }) { createDocument.launch(name) }
                }
            }
            "pickFile" -> {
                if (pendingPick != null) {
                    result.error("busy", "A file is being chosen.", null)
                } else {
                    pendingPick = result
                    launchOr(result, { pendingPick = null }) { openDocument.launch(arrayOf("*/*")) }
                }
            }
            else -> return false
        }
        return true
    }
}
