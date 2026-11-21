package io.github.swz0103.expensetracker

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ExifInterface
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * A receipt photo as a camera saves it (PhotosHandler.kt): a JPEG on disk
 * with the turn in its EXIF tags, read back by the phone's own decoder.
 */
@RunWith(AndroidJUnit4::class)
class ReceiptPhotoDeviceTest {
    private val cache = InstrumentationRegistry.getInstrumentation().targetContext.cacheDir

    private fun photo(width: Int, height: Int, orientation: Int): File {
        val file = File(cache, "receipt-test.jpg")
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565)
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 80, it) }
        bitmap.recycle()
        ExifInterface(file.absolutePath).apply {
            setAttribute(ExifInterface.TAG_ORIENTATION, orientation.toString())
            saveAttributes()
        }
        return file
    }

    @Test
    fun aSidewaysPhotoIsReadAsTurnedAQuarter() {
        val file = photo(800, 600, ExifInterface.ORIENTATION_ROTATE_90)
        val tag = ExifInterface(file.absolutePath)
            .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        assertEquals(90f, ReceiptPhoto.turnFor(tag), 0f)
        file.delete()
    }

    @Test
    fun aLargePhotoIsDecodedSmallerAndEndsAtTheLongSide() {
        val file = photo(4000, 2000, ExifInterface.ORIENTATION_NORMAL)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        val sample = ReceiptPhoto.sampleFor(bounds.outWidth, bounds.outHeight)
        assertEquals(2, sample)
        val decoded = BitmapFactory.decodeFile(
            file.absolutePath,
            BitmapFactory.Options().apply { inSampleSize = sample },
        )
        val scale = ReceiptPhoto.scaleFor(decoded.width, decoded.height)
        assertEquals(ReceiptPhoto.LONG_SIDE, Math.round(maxOf(decoded.width, decoded.height) * scale))
        decoded.recycle()
        file.delete()
    }
}
