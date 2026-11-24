package io.github.swz0103.expensetracker

import java.io.ByteArrayInputStream
import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Test

/** Review 27 finding 1: only a backup's start is read to see its header. */
class FolderFilesTest {
    /** A stream that hands out at most [step] bytes per read, as some providers do. */
    private class Trickle(private val bytes: ByteArray, private val step: Int) : InputStream() {
        private var at = 0
        override fun read(): Int = if (at < bytes.size) bytes[at++].toInt() and 0xff else -1
        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (at >= bytes.size) return -1
            val n = minOf(len, step, bytes.size - at)
            System.arraycopy(bytes, at, b, off, n)
            at += n
            return n
        }
    }

    @Test
    fun readsUpToTheLimitAcrossShortReads() {
        val bytes = ByteArray(10) { it.toByte() }
        // 3 bytes a read: 3 + 3 + 1 to reach 7.
        assertArrayEquals(
            byteArrayOf(0, 1, 2, 3, 4, 5, 6),
            FolderFiles.readUpTo(Trickle(bytes, 3), 7),
        )
    }

    @Test
    fun aShorterFileGivesWhatItHas() {
        assertArrayEquals(
            byteArrayOf(1, 2, 3),
            FolderFiles.readUpTo(ByteArrayInputStream(byteArrayOf(1, 2, 3)), 256 * 1024),
        )
        assertArrayEquals(
            byteArrayOf(),
            FolderFiles.readUpTo(ByteArrayInputStream(byteArrayOf(1, 2, 3)), 0),
        )
    }
}
