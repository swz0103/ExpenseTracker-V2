package io.github.swz0103.expensetracker

import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * A folder the person chose once, such as one in Documents, that the app
 * may keep writing backups into (lib/src/app/android/folder.dart): the
 * system's folder chooser, then a lasting permission to read and write
 * it. Files are written, listed and deleted there by the system's
 * documents API; the work runs off the main thread.
 */
class FolderPart(private val activity: FragmentActivity) : ChannelPart {
    private var pendingFolder: MethodChannel.Result? = null

    private val openTree =
        activity.registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            val result = pendingFolder ?: return@registerForActivityResult
            pendingFolder = null
            if (uri == null) {
                result.success(null)
                return@registerForActivityResult
            }
            try {
                activity.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
                result.success(mapOf("uri" to uri.toString(), "name" to nameOf(uri)))
            } catch (e: Exception) {
                result.error("folder", e.message, null)
            }
        }

    /** The folder's name as the chooser showed it. */
    private fun nameOf(tree: Uri): String {
        val folder = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        activity.contentResolver.query(
            folder,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { if (it.moveToFirst()) return it.getString(0) ?: "" }
        return tree.lastPathSegment ?: ""
    }

    /** Runs [work] off the main thread and answers [result] on it. */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        Thread {
            try {
                val value = work()
                activity.runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("folder", e.message, null) }
            }
        }.start()
    }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        val tree = call.argument<String>("uri")?.let(Uri::parse)
        when (call.method) {
            "pickFolder" -> {
                if (pendingFolder != null) {
                    result.error("busy", "A folder is being chosen.", null)
                } else {
                    pendingFolder = result
                    launchOr(result, { pendingFolder = null }) { openTree.launch(null) }
                }
            }
            "folderAllowed" ->
                if (tree == null) result.success(false)
                else result.success(FolderFiles.allowed(activity.contentResolver, tree))
            "forgetFolder" -> {
                if (tree != null && FolderFiles.allowed(activity.contentResolver, tree)) {
                    activity.contentResolver.releasePersistableUriPermission(
                        tree,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                    )
                }
                result.success(null)
            }
            "listFolder" ->
                if (tree == null) result.error("bad-arguments", "uri is required", null)
                else background(result) { FolderFiles.list(activity.contentResolver, tree) }
            "writeToFolder" -> {
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                if (tree == null || path == null || name == null) {
                    result.error("bad-arguments", "uri, path and name are required", null)
                } else {
                    background(result) {
                        FolderFiles.write(activity.contentResolver, tree, File(path), name)
                        null
                    }
                }
            }
            "deleteInFolder" -> {
                val id = call.argument<String>("id")
                if (tree == null || id == null) {
                    result.error("bad-arguments", "uri and id are required", null)
                } else {
                    background(result) {
                        FolderFiles.delete(activity.contentResolver, tree, id)
                        null
                    }
                }
            }
            else -> return false
        }
        return true
    }
}
