package io.github.swz0103.expensetracker

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files

/** AND-05: an upload to Drive cut short goes on from where it stopped. */
class UploadSessionTest {
    private val address = "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=x"

    @Test
    fun aSessionIsKeptAndReadBackAndOnlyForItsFile() {
        val dir = Files.createTempDirectory("upload").toFile()
        try {
            val backup = File(dir, "記帳本-20261123-101500000.etbk").apply { writeBytes(ByteArray(10)) }
            val store = UploadSession.In(File(dir, UploadSession.FILE))
            assertNull(store.read())
            store.write(UploadSession(address, backup.name, 10))
            val read = store.read()!!
            assertEquals(UploadSession(address, backup.name, 10), read)
            assertTrue(read.fits(backup))
            // Another backup, or this one written again larger: not it.
            assertFalse(read.fits(File(dir, "other.etbk").apply { writeBytes(ByteArray(10)) }))
            backup.writeBytes(ByteArray(11))
            assertFalse(read.fits(backup))
            store.clear()
            assertNull(store.read())
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun anythingButThreeLinesIsNoSession() {
        assertNull(UploadSession.decode(""))
        assertNull(UploadSession.decode("$address\nname"))
        assertNull(UploadSession.decode("$address\nname\nten"))
        assertNull(UploadSession.decode("$address\nname\n-1"))
        assertEquals(UploadSession(address, "n", 5), UploadSession.decode("$address\nn\n5"))
    }

    @Test
    fun driveSaysWhereToGoOnFrom() {
        // Drive holds bytes 0 to 524,287: the next is 524,288.
        assertEquals(524_288L, ResumableUpload.nextByte("bytes=0-524287"))
        assertEquals(0L, ResumableUpload.nextByte(null))
        assertEquals(0L, ResumableUpload.nextByte("bytes=5-9"))
        assertEquals("bytes */1000", ResumableUpload.query(1000))
        // From byte 600 of 1,000: 600 to 999.
        assertEquals("bytes 600-999/1000", ResumableUpload.rest(600, 1000))
        assertEquals(308, ResumableUpload.INCOMPLETE)
    }

    @Test
    fun theRestIsReadFromWhereDriveStopped() {
        val input = ByteArrayInputStream(byteArrayOf(1, 2, 3, 4, 5))
        ResumableUpload.skip(input, 3)
        assertArrayEquals(byteArrayOf(4, 5), input.readBytes())
    }
}
