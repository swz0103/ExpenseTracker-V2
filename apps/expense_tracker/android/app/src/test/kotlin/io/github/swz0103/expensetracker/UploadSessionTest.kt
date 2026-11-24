package io.github.swz0103.expensetracker

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.File
import java.io.IOException
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
        assertEquals("bytes 600-999/1000", ResumableUpload.part(600, 999, 1000))
        assertEquals("bytes */0", ResumableUpload.part(0, -1, 0))
        assertEquals(308, ResumableUpload.INCOMPLETE)
    }

    @Test
    fun aLargeBackupGoesInPartsOfEightMebibytes() {
        // Review 21 finding 2: 20 MiB (20,971,520 bytes) from byte 0 is
        // 0..8,388,607, 8,388,608..16,777,215, 16,777,216..20,971,519.
        val size = 20_971_520L
        val sent = mutableListOf<Pair<Long, Long>>()
        ResumableUpload.inParts(0, size, { false }) { first, last ->
            sent.add(first to last)
            if (last == size - 1) null else last + 1
        }
        assertEquals(
            listOf(
                0L to 8_388_607L,
                8_388_608L to 16_777_215L,
                16_777_216L to 20_971_519L,
            ),
            sent,
        )
        assertEquals(8_388_608L, ResumableUpload.PART)
    }

    @Test
    fun aPartGoesOnFromWhatDriveHolds() {
        // Drive kept only 262,144 bytes (256 KiB) of the first part.
        val sent = mutableListOf<Long>()
        ResumableUpload.inParts(0, 1_000_000L, { false }) { first, _ ->
            sent.add(first)
            if (first == 0L) 262_144L else null
        }
        assertEquals(listOf(0L, 262_144L), sent)
    }

    @Test
    fun aStoppedRunEndsBetweenTwoParts() {
        var parts = 0
        var stop = false
        try {
            ResumableUpload.inParts(0, 20_971_520L, { stop }) { _, last ->
                parts++
                stop = true
                last + 1
            }
            fail("not stopped")
        } catch (e: BackgroundWork.Stopped) {
            assertEquals(1, parts)
        }
    }

    @Test
    fun aPartDriveTookNothingOfIsNotSentForEver() {
        try {
            ResumableUpload.inParts(100, 1_000L, { false }) { first, _ -> first }
            fail("sent for ever")
        } catch (e: IOException) {
            assertTrue(e.message!!.contains("100"))
        }
    }

    @Test
    fun aPartIsCopiedToTheByte() {
        val out = ByteArrayOutputStream()
        ResumableUpload.copy(ByteArrayInputStream(byteArrayOf(1, 2, 3, 4, 5)), out, 3)
        assertArrayEquals(byteArrayOf(1, 2, 3), out.toByteArray())
        try {
            ResumableUpload.copy(ByteArrayInputStream(byteArrayOf(1)), ByteArrayOutputStream(), 2)
            fail("short file")
        } catch (e: EOFException) {
            // The file shrank under the upload.
        }
    }

    @Test
    fun theRestIsReadFromWhereDriveStopped() {
        val input = ByteArrayInputStream(byteArrayOf(1, 2, 3, 4, 5))
        ResumableUpload.skip(input, 3)
        assertArrayEquals(byteArrayOf(4, 5), input.readBytes())
    }
}
