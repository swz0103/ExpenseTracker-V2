package io.github.swz0103.expensetracker

import java.io.File
import java.io.InputStream

/**
 * An upload to Google Drive under way: where Drive takes it ([location],
 * one of Google's upload addresses, good for a week) and the file it is
 * of, by [name] and [size], so an upload cut short goes on from where it
 * stopped, and only for that same file ([DriveUploader]; AND-05).
 */
internal data class UploadSession(val location: String, val name: String, val size: Long) {
    /** Whether this upload is of [file]. */
    fun fits(file: File): Boolean = file.name == name && file.length() == size

    /** Three lines: the address, the name, the size. */
    fun encode(): String = "$location\n$name\n$size"

    /** Where an upload under way is kept between runs. */
    interface Store {
        fun read(): UploadSession?
        fun write(session: UploadSession)
        fun clear()
    }

    /** Kept in [file], beside the backup in the outbox. */
    class In(private val file: File) : Store {
        override fun read(): UploadSession? = try {
            if (file.exists()) decode(file.readText()) else null
        } catch (e: Exception) {
            null
        }

        override fun write(session: UploadSession) {
            val next = File(file.parentFile, "${file.name}.new")
            next.writeText(session.encode())
            if (!next.renameTo(file)) next.delete()
        }

        override fun clear() {
            file.delete()
        }
    }

    companion object {
        /** The file in the outbox an upload under way is kept in. */
        const val FILE = "upload.txt"

        /** What [encode] wrote; null for anything else. */
        fun decode(text: String): UploadSession? {
            val lines = text.split('\n')
            if (lines.size != 3) return null
            val size = lines[2].toLongOrNull() ?: return null
            if (lines[0].isEmpty() || lines[1].isEmpty() || size < 0) return null
            return UploadSession(lines[0], lines[1], size)
        }
    }
}

/**
 * Google's resumable upload, as far as going on after a cut needs
 * (developers.google.com/drive/api/guides/manage-uploads#resumable).
 */
internal object ResumableUpload {
    /** Drive's answer while it holds part of the upload: Resume Incomplete. */
    const val INCOMPLETE = 308

    /** The `Content-Range` that asks how much of [size] bytes Drive holds. */
    fun query(size: Long): String = "bytes */$size"

    /** The `Content-Range` of the bytes from [from] to the end of [size]. */
    fun rest(from: Long, size: Long): String = "bytes $from-${size - 1}/$size"

    /**
     * The first byte Drive does not hold, from the `Range` it answered
     * (`bytes=0-524287`); 0 when it holds none (no `Range`) or answered
     * something else.
     */
    fun nextByte(range: String?): Long {
        val match = Regex("^bytes=0-(\\d+)$").matchEntire(range?.trim() ?: return 0) ?: return 0
        return (match.groupValues[1].toLongOrNull() ?: return 0) + 1
    }

    /** Skips the first [count] bytes of [input]. */
    fun skip(input: InputStream, count: Long) {
        var left = count
        while (left > 0) {
            val skipped = input.skip(left)
            if (skipped <= 0) {
                if (input.read() < 0) throw java.io.EOFException("The file is shorter than the upload.")
                left--
            } else {
                left -= skipped
            }
        }
    }
}
