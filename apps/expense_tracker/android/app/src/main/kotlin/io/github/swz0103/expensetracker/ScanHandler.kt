package io.github.swz0103.expensetracker

import androidx.fragment.app.FragmentActivity
import com.google.android.gms.common.moduleinstall.InstallStatusListener
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate.InstallState
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScanner
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reads a QR code, such as one of a paper e-invoice's two, with Google's
 * code scanner (lib/src/app/android/scanner_adapter.dart). The scanner is Google
 * Play services' own screen: the app needs no camera permission and sees
 * only the code's text.
 *
 * The scanner is a module Play services fetches on demand. An app
 * installed from Play has it fetched with it (the manifest asks); one
 * installed from its APK does not, so the first scan asks for it, waits
 * for it to arrive and then opens it. Errors are answered with a code
 * the app words: `install` when the module cannot be fetched (Play
 * services off or out of date), `scan` when the scanner itself fails.
 */
class ScanHandler(private val activity: FragmentActivity) : ChannelHandler {
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
            val scanner = GmsBarcodeScanning.getClient(activity, options)
            val modules = ModuleInstall.getClient(activity)
            modules.areModulesAvailable(scanner)
                .addOnSuccessListener { if (it.areModulesAvailable()) scan(scanner) else fetch(scanner) }
                .addOnFailureListener { e -> finish { it.error("install", e.message, null) } }
        } catch (e: Exception) {
            finish { it.error("install", e.message, null) }
        }
        return true
    }

    /** Asks Play services for the scanner, then opens it once it is here. */
    private fun fetch(scanner: GmsBarcodeScanner) {
        val modules = ModuleInstall.getClient(activity)
        val listener = object : InstallStatusListener {
            override fun onInstallStatusUpdated(update: ModuleInstallStatusUpdate) {
                when (update.installState) {
                    InstallState.STATE_COMPLETED -> {
                        modules.unregisterListener(this)
                        scan(scanner)
                    }
                    InstallState.STATE_FAILED, InstallState.STATE_CANCELED -> {
                        modules.unregisterListener(this)
                        finish { it.error("install", "state ${update.installState}", null) }
                    }
                    else -> {}
                }
            }
        }
        val request = ModuleInstallRequest.newBuilder()
            .addApi(scanner)
            .setListener(listener)
            .build()
        modules.installModules(request)
            .addOnSuccessListener {
                if (it.areModulesAlreadyInstalled()) {
                    modules.unregisterListener(listener)
                    scan(scanner)
                }
            }
            .addOnFailureListener { e -> finish { it.error("install", e.message, null) } }
    }

    private fun scan(scanner: GmsBarcodeScanner) {
        try {
            scanner.startScan()
                .addOnSuccessListener { code -> finish { it.success(code.rawValue) } }
                .addOnCanceledListener { finish { it.success(null) } }
                .addOnFailureListener { e -> finish { it.error("scan", e.message, null) } }
        } catch (e: Exception) {
            finish { it.error("scan", e.message, null) }
        }
    }

    private fun finish(answer: (MethodChannel.Result) -> Unit) {
        val result = pending ?: return
        pending = null
        activity.runOnUiThread { answer(result) }
    }
}
