package io.github.swz0103.expensetracker

import android.media.ExifInterface

/**
 * How [PhotosHandler] sizes and turns a receipt photo, apart from the
 * bitmaps so it can be tested: at most [LONG_SIDE] pixels on its long
 * side, upright by its EXIF orientation.
 */
object ReceiptPhoto {
    const val LONG_SIDE = 1600

    /**
     * The power of two to decode at, the largest that still leaves the long
     * side at [LONG_SIDE] or more, so the last scaling only shrinks.
     */
    fun sampleFor(width: Int, height: Int): Int {
        var sample = 1
        while (maxOf(width, height) / (sample * 2) >= LONG_SIDE) sample *= 2
        return sample
    }

    /** What to scale a decoded photo by: down to [LONG_SIDE], never up. */
    fun scaleFor(width: Int, height: Int): Float {
        val longSide = maxOf(width, height)
        return if (longSide > LONG_SIDE) LONG_SIDE.toFloat() / longSide else 1f
    }

    /** The degrees to turn a photo by its EXIF orientation tag. */
    fun turnFor(orientation: Int): Float = when (orientation) {
        ExifInterface.ORIENTATION_ROTATE_90 -> 90f
        ExifInterface.ORIENTATION_ROTATE_180 -> 180f
        ExifInterface.ORIENTATION_ROTATE_270 -> 270f
        else -> 0f
    }
}
