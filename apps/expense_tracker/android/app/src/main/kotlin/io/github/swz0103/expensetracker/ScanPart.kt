package io.github.swz0103.expensetracker

import androidx.fragment.app.FragmentActivity
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reads a QR code, such as one of a paper e-invoice's two, with Google's
 * code scanner (lib/src/app/android/scan.dart). The scanner is Google
 * Play services' own screen: the app needs no camera permission and sees
 * only the code's text.
 */
class ScanPart(private val activity: FragmentActivity) : ChannelPart {
    private var pending: MethodChannel.Result? = null

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != "scanQr") return false
        if (pending != null) {
            result.error("busy", "A code is being scanned.", null)
            return true
        }
        pending = result
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build()
        try {
            GmsBarcodeScanning.getClient(activity, options).startScan()
                .addOnSuccessListener { code -> finish { it.success(code.rawValue) } }
                .addOnCanceledListener { finish { it.success(null) } }
                .addOnFailureListener { e -> finish { it.error("scan", e.message, null) } }
        } catch (e: Exception) {
            finish { it.error("unavailable", e.message, null) }
        }
        return true
    }

    private fun finish(answer: (MethodChannel.Result) -> Unit) {
        val result = pending ?: return
        pending = null
        answer(result)
    }
}
