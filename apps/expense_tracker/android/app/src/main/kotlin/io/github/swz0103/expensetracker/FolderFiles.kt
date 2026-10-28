package io.github.swz0103.expensetracker

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File

/**
 * Files in a folder the person chose (FolderPart.kt), through the
 * system's documents API: used by the app while it is open and by the
 * background job (BackupWorker.kt) while it is not.
 */
internal object FolderFiles {
    /** Whether the lasting permission for [tree] is still held. */
    fun allowed(resolver: ContentResolver, tree: Uri): Boolean =
        resolver.persistedUriPermissions.any { it.uri == tree && it.isWritePermission }

    /** The files directly in [tree]: id, name, last change in ms. */
    fun list(resolver: ContentResolver, tree: Uri): List<Map<String, Any>> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        val found = mutableListOf<Map<String, Any>>()
        resolver.query(
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

    /** Copies [file] into [tree] as [name]. */
    fun write(resolver: ContentResolver, tree: Uri, file: File, name: String) {
        val folder = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        val made = DocumentsContract.createDocument(
            resolver,
            folder,
            "application/octet-stream",
            name,
        ) ?: throw IllegalStateException("The folder cannot be written.")
        try {
            val output = resolver.openOutputStream(made)
                ?: throw IllegalStateException("The folder cannot be written.")
            output.use { file.inputStream().use { input -> input.copyTo(it) } }
        } catch (e: Exception) {
            // Half a backup is worse than none.
            DocumentsContract.deleteDocument(resolver, made)
            throw e
        }
    }

    fun delete(resolver: ContentResolver, tree: Uri, id: String) {
        val document = DocumentsContract.buildDocumentUriUsingTree(tree, id)
        DocumentsContract.deleteDocument(resolver, document)
    }
}
