package io.github.swz0103.expensetracker

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** A backup and its token go only to Google's own upload host (SEC-13). */
class DriveUploaderTest {
    @Test
    fun googleUploadAddressesAreAccepted() {
        assertTrue(
            DriveUploader.isGoogleUpload(
                "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=x",
            ),
        )
        assertTrue(DriveUploader.isGoogleUpload("https://content.googleapis.com/upload"))
    }

    @Test
    fun otherHostsAndPlainHttpAreRefused() {
        assertFalse(DriveUploader.isGoogleUpload("http://www.googleapis.com/upload"))
        assertFalse(DriveUploader.isGoogleUpload("https://googleapis.com.example.org/upload"))
        assertFalse(DriveUploader.isGoogleUpload("https://evilgoogleapis.com/upload"))
        assertFalse(DriveUploader.isGoogleUpload("not a url"))
    }
}
