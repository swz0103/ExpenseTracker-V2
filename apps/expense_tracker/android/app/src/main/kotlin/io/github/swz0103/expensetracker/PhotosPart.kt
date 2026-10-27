package io.github.swz0103.expensetracker

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Receipt photos from the camera or the gallery, made smaller and upright
 * before the app seals them (lib/src/app/android/photos.dart).
 */
class PhotosPart(private val activity: FragmentActivity) : ChannelPart {
    private var pendingPhoto: MethodChannel.Result? = null

    /** Where the camera writes before the photo is made smaller. */
    private val cameraFile: File
        get() = File(activity.cacheDir, "camera").apply { mkdirs() }.resolve("receipt.jpg")

    // When the app was closed while the camera or picker was open, nothing
    // waits for the photo any more (pendingPhoto is null): it is dropped
    // rather than left in the cache.
    private val takePicture =
        activity.registerForActivityResult(ActivityResultContracts.TakePicture()) { taken ->
            if (taken && pendingPhoto != null) {
                keepPhoto(Uri.fromFile(cameraFile))
            } else {
                cameraFile.delete()
                finishPhoto(null)
            }
        }

    private val pickImage =
        activity.registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
            if (uri != null && pendingPhoto != null) keepPhoto(uri) else finishPhoto(null)
        }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != "takePhoto") return false
        if (pendingPhoto != null) {
            result.error("busy", "A photo is being taken.", null)
            return true
        }
        pendingPhoto = result
        val camera = call.argument<Boolean>("camera") == true
        launchOr(result, { pendingPhoto = null }) {
            if (camera) {
                val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.files", cameraFile)
                takePicture.launch(uri)
            } else {
                pickImage.launch("image/*")
            }
        }
        return true
    }

    private fun finishPhoto(name: String?) {
        val result = pendingPhoto ?: return
        pendingPhoto = null
        result.success(name)
    }

    /**
     * Makes a receipt photo ready to keep: turned upright, at most 1600
     * pixels on its long side, as a JPEG in the cache. The app seals it
     * into the private `receipts` folder and deletes this copy. Off the
     * main thread.
     */
    private fun keepPhoto(source: Uri) {
        Thread {
            try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                activity.contentResolver.openInputStream(source)?.use {
                    BitmapFactory.decodeStream(it, null, bounds)
                }
                var sample = 1
                while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1600) sample *= 2
                val decoded = activity.contentResolver.openInputStream(source)?.use {
                    BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
                } ?: throw IllegalStateException("The photo cannot be read.")
                // Cameras save sideways and note the turn in the EXIF tags.
                val turn = if (Build.VERSION.SDK_INT < 24) {
                    0f
                } else {
                    activity.contentResolver.openInputStream(source)?.use {
                        when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)) {
                            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                            else -> 0f
                        }
                    } ?: 0f
                }
                val longSide = maxOf(decoded.width, decoded.height)
                val scale = if (longSide > 1600) 1600f / longSide else 1f
                val matrix = Matrix().apply {
                    postScale(scale, scale)
                    postRotate(turn)
                }
                val photo = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
                val ready = File(activity.cacheDir, "receipt-ready.jpg")
                ready.outputStream().use { photo.compress(Bitmap.CompressFormat.JPEG, 82, it) }
                cameraFile.delete()
                activity.runOnUiThread { finishPhoto(ready.absolutePath) }
            } catch (e: Throwable) {
                // Any failure, running out of memory on a huge photo
                // included, ends the request, so takePhoto is not left busy.
                activity.runOnUiThread {
                    val result = pendingPhoto
                    pendingPhoto = null
                    result?.error("photo", e.message, null)
                }
            }
        }.start()
    }
}
