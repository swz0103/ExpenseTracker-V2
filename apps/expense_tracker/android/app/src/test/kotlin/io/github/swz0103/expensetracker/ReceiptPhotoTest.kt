package io.github.swz0103.expensetracker

import android.media.ExifInterface
import org.junit.Assert.assertEquals
import org.junit.Test

/** How a receipt photo is sized and turned (PhotosHandler.kt). */
class ReceiptPhotoTest {
    @Test
    fun aSmallPhotoIsDecodedWholeAndNotGrown() {
        assertEquals(1, ReceiptPhoto.sampleFor(1200, 900))
        assertEquals(1f, ReceiptPhoto.scaleFor(1200, 900), 0f)
        assertEquals(1f, ReceiptPhoto.scaleFor(1600, 1200), 0f)
    }

    @Test
    fun aLargePhotoIsDecodedSmallerButNeverBelowTheLongSide() {
        // 4000 / 2 = 2000 still ≥ 1600; 4000 / 4 = 1000 would be too small.
        assertEquals(2, ReceiptPhoto.sampleFor(4000, 3000))
        assertEquals(4, ReceiptPhoto.sampleFor(3000, 8000))
        for (side in listOf(1600, 2000, 3199, 3200, 6400, 12000)) {
            val sample = ReceiptPhoto.sampleFor(side, side / 2)
            assertEquals(true, side / sample >= ReceiptPhoto.LONG_SIDE)
        }
    }

    @Test
    fun theLongSideEndsAt1600() {
        assertEquals(1600f, 2000 * ReceiptPhoto.scaleFor(2000, 1500), 0.01f)
        assertEquals(1600f, 4000 * ReceiptPhoto.scaleFor(3000, 4000), 0.01f)
    }

    @Test
    fun aSidewaysPhotoIsTurnedUpright() {
        assertEquals(90f, ReceiptPhoto.turnFor(ExifInterface.ORIENTATION_ROTATE_90), 0f)
        assertEquals(180f, ReceiptPhoto.turnFor(ExifInterface.ORIENTATION_ROTATE_180), 0f)
        assertEquals(270f, ReceiptPhoto.turnFor(ExifInterface.ORIENTATION_ROTATE_270), 0f)
        assertEquals(0f, ReceiptPhoto.turnFor(ExifInterface.ORIENTATION_NORMAL), 0f)
        assertEquals(0f, ReceiptPhoto.turnFor(ExifInterface.ORIENTATION_UNDEFINED), 0f)
    }
}
