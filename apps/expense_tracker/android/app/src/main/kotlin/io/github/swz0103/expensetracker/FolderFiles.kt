package io.github.swz0103.expensetracker

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File
import java.io.InputStream

/**
 * Files in a folder the person chose (FolderHandler.kt), through the
 * system's documents API: used by the app while it is open and by the
 * background job (BackupWorker.kt) while it is not.
 */
internal object FolderFiles {
    /** How much is copied between two looks at whether the run was stopped (1 MiB). */
    private const val COPY_BUFFER = 1024 * 1024

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

    /**
     * Copies [file] into [tree] as [name]; a copy [stopped] on the way
     * ends with [BackgroundWork.Stopped], and the half copy is taken away.
     */
    fun write(
        resolver: ContentResolver,
        tree: Uri,
        file: File,
        name: String,
        stopped: () -> Boolean = { false },
    ) {
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
            output.use { out ->
                file.inputStream().use { input ->
                    val buffer = ByteArray(COPY_BUFFER)
                    while (true) {
                        if (stopped()) throw BackgroundWork.Stopped()
                        val read = input.read(buffer)
                        if (read < 0) break
                        out.write(buffer, 0, read)
                    }
                }
            }
        } catch (e: Exception) {
            // Half a backup is worse than none.
            DocumentsContract.deleteDocument(resolver, made)
            throw e
        }
    }

    /**
     * The first bytes of the file [id] in [tree], at most [bytes] of them:
     * enough to read a backup's header without copying the whole file.
     */
    fun head(resolver: ContentResolver, tree: Uri, id: String, bytes: Int): ByteArray {
        val document = DocumentsContract.buildDocumentUriUsingTree(tree, id)
        val input = resolver.openInputStream(document)
            ?: throw IllegalStateException("The file cannot be read.")
        return input.use { readUpTo(it, bytes) }
    }

    /** Up to [bytes] bytes from the start of [input]; fewer when it ends sooner. */
    fun readUpTo(input: InputStream, bytes: Int): ByteArray {
        val buffer = ByteArray(bytes.coerceAtLeast(0))
        var filled = 0
        while (filled < buffer.size) {
            val read = input.read(buffer, filled, buffer.size - filled)
            if (read < 0) break
            filled += read
        }
        return buffer.copyOf(filled)
    }

    fun delete(resolver: ContentResolver, tree: Uri, id: String) {
        val document = DocumentsContract.buildDocumentUriUsingTree(tree, id)
        DocumentsContract.deleteDocument(resolver, document)
    }
}
