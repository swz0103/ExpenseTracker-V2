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

    /** Whether the lasting permission for [tree] is still held. */
    private fun allowed(tree: Uri): Boolean =
        activity.contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isWritePermission
        }

    /** The files directly in [tree]: id, name, last change in ms. */
    private fun list(tree: Uri): List<Map<String, Any>> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        val found = mutableListOf<Map<String, Any>>()
        activity.contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            ),
            null,
            null,
            null,
        )?.use {
            while (it.moveToNext()) {
                found.add(
                    mapOf(
                        "id" to (it.getString(0) ?: continue),
                        "name" to (it.getString(1) ?: ""),
                        "modified" to it.getLong(2),
                    ),
                )
            }
        }
        return found
    }

    /** Copies the file at [path] into [tree] as [name]. */
    private fun write(tree: Uri, path: String, name: String) {
        val folder = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        val made = DocumentsContract.createDocument(
            activity.contentResolver,
            folder,
            "application/octet-stream",
            name,
        ) ?: throw IllegalStateException("The folder cannot be written.")
        try {
            val output = activity.contentResolver.openOutputStream(made)
                ?: throw IllegalStateException("The folder cannot be written.")
            output.use { File(path).inputStream().use { input -> input.copyTo(it) } }
        } catch (e: Exception) {
            // Half a backup is worse than none.
            DocumentsContract.deleteDocument(activity.contentResolver, made)
            throw e
        }
    }

    private fun delete(tree: Uri, id: String) {
        val document = DocumentsContract.buildDocumentUriUsingTree(tree, id)
        DocumentsContract.deleteDocument(activity.contentResolver, document)
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
                if (tree == null) result.success(false) else result.success(allowed(tree))
            "forgetFolder" -> {
                if (tree != null && allowed(tree)) {
                    activity.contentResolver.releasePersistableUriPermission(
                        tree,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                    )
                }
                result.success(null)
            }
            "listFolder" ->
                if (tree == null) result.error("bad-arguments", "uri is required", null)
                else background(result) { list(tree) }
            "writeToFolder" -> {
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                if (tree == null || path == null || name == null) {
                    result.error("bad-arguments", "uri, path and name are required", null)
                } else {
                    background(result) { write(tree, path, name); null }
                }
            }
            "deleteInFolder" -> {
                val id = call.argument<String>("id")
                if (tree == null || id == null) {
                    result.error("bad-arguments", "uri and id are required", null)
                } else {
                    background(result) { delete(tree, id); null }
                }
            }
            else -> return false
        }
        return true
    }
}
