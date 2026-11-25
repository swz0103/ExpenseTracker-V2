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
 * may keep writing backups into (lib/src/app/android/folder_adapter.dart): the
 * system's folder chooser, then a lasting permission to read and write
 * it. Files are written, listed and deleted there by the system's
 * documents API; the work runs off the main thread.
 */
class FolderHandler(private val activity: FragmentActivity) : ChannelHandler {
    private var pendingFolder: MethodChannel.Result? = null

    private val openTree =
        activity.registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            val result = pendingFolder ?: return@registerForActivityResult
            pendingFolder = null
            if (uri == null) {
                result.success(null)
                return@registerForActivityResult
            }
            // The permission and the folder's name ask the documents
            // provider, which can be slow: off the main thread.
            offMain.run(
                {
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                    )
                    mapOf("uri" to uri.toString(), "name" to nameOf(uri))
                },
                { result.success(it) },
                // Android keeps no permission for some places, such as the
                // storage's top or Download since Android 11.
                { result.error("rejected", it.message, null) },
            )
        }

    /** Where the chooser opens: Documents on the phone's own storage. */
    private val documents: Uri =
        DocumentsContract.buildDocumentUri(
            "com.android.externalstorage.documents",
            "primary:Documents",
        )

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
    private fun background(result: MethodChannel.Result, work: () -> Any?) =
        offMain.answer(result, "folder", work)

    private val offMain = OffMain.of(activity)

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        val tree = call.argument<String>("uri")?.let(Uri::parse)
        when (call.method) {
            "pickFolder" -> {
                if (pendingFolder != null) {
                    result.error("busy", "A folder is being chosen.", null)
                } else {
                    pendingFolder = result
                    launchOr(result, { pendingFolder = null }) { openTree.launch(documents) }
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
            "readFolderHead" -> {
                val id = call.argument<String>("id")
                val bytes = call.argument<Int>("bytes")
                if (tree == null || id == null || bytes == null) {
                    result.error("bad-arguments", "uri, id and bytes are required", null)
                } else {
                    background(result) { FolderFiles.head(activity.contentResolver, tree, id, bytes) }
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
