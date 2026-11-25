package io.github.swz0103.expensetracker

import android.os.Handler
import android.os.Looper
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
 * for it to arrive and then opens it. `scanReady` says whether it is
 * here already, so the app can explain the wait before `scanQr` starts
 * it. Errors are answered with a code the app words and, as the error's
 * details, a reason it keeps in its error log ([ScanFault]): `install`
 * when the module cannot be fetched (Play services off or out of date,
 * no network, no room, or no answer within [FETCH_TIMEOUT_MS]), `scan`
 * when the scanner itself fails.
 */
class ScanHandler(private val activity: FragmentActivity) : ChannelHandler {
    private var pending: MethodChannel.Result? = null

    /** Which scan is under way: an answer for an earlier one is dropped. */
    private var attempt = 0

    private val main = Handler(Looper.getMainLooper())

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "scanReady" -> ready(result)
            "scanQr" -> start(result)
            else -> return false
        }
        return true
    }

    private fun scanner(): GmsBarcodeScanner = GmsBarcodeScanning.getClient(
        activity,
        GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build(),
    )

    /** Whether the scanner is on the phone already. */
    private fun ready(result: MethodChannel.Result) {
        try {
            ModuleInstall.getClient(activity).areModulesAvailable(scanner())
                .addOnSuccessListener { result.success(it.areModulesAvailable()) }
                .addOnFailureListener { e -> result.error("install", e.message, ScanFault.reason(e)) }
        } catch (e: Exception) {
            result.error("install", e.message, ScanFault.reason(e))
        }
    }

    private fun start(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A code is being scanned.", null)
            return
        }
        pending = result
        val id = ++attempt
        try {
            val scanner = scanner()
            ModuleInstall.getClient(activity).areModulesAvailable(scanner)
                .addOnSuccessListener {
                    if (it.areModulesAvailable()) scan(id, scanner) else fetch(id, scanner)
                }
                .addOnFailureListener { e -> fail(id, "install", e) }
        } catch (e: Exception) {
            fail(id, "install", e)
        }
    }

    /** Asks Play services for the scanner, then opens it once it is here. */
    private fun fetch(id: Int, scanner: GmsBarcodeScanner) {
        val modules = ModuleInstall.getClient(activity)
        lateinit var giveUp: Runnable
        val listener = object : InstallStatusListener {
            override fun onInstallStatusUpdated(update: ModuleInstallStatusUpdate) {
                when (update.installState) {
                    InstallState.STATE_COMPLETED -> {
                        modules.unregisterListener(this)
                        main.removeCallbacks(giveUp)
                        scan(id, scanner)
                    }
                    InstallState.STATE_FAILED, InstallState.STATE_CANCELED -> {
                        modules.unregisterListener(this)
                        main.removeCallbacks(giveUp)
                        finish(id) {
                            it.error(
                                "install",
                                "state ${update.installState}",
                                ScanFault.install(update.installState, update.errorCode),
                            )
                        }
                    }
                    else -> {}
                }
            }
        }
        // A download that never ends would leave the app waiting, and
        // every later scan refused as busy.
        giveUp = Runnable {
            modules.unregisterListener(listener)
            finish(id) { it.error("install", "no answer", ScanFault.TIMEOUT) }
        }
        main.postDelayed(giveUp, FETCH_TIMEOUT_MS)
        val request = ModuleInstallRequest.newBuilder()
            .addApi(scanner)
            .setListener(listener)
            .build()
        modules.installModules(request)
            .addOnSuccessListener {
                if (it.areModulesAlreadyInstalled()) {
                    modules.unregisterListener(listener)
                    main.removeCallbacks(giveUp)
                    scan(id, scanner)
                }
            }
            .addOnFailureListener { e ->
                modules.unregisterListener(listener)
                main.removeCallbacks(giveUp)
                fail(id, "install", e)
            }
    }

    private fun scan(id: Int, scanner: GmsBarcodeScanner) {
        // Given up on, or answered already: the scanner is not opened for
        // a scan nobody waits for.
        if (id != attempt || pending == null) return
        try {
            scanner.startScan()
                .addOnSuccessListener { code -> finish(id) { it.success(code.rawValue) } }
                .addOnCanceledListener { finish(id) { it.success(null) } }
                .addOnFailureListener { e -> fail(id, "scan", e) }
        } catch (e: Exception) {
            fail(id, "scan", e)
        }
    }

    private fun fail(id: Int, code: String, error: Exception) =
        finish(id) { it.error(code, error.message, ScanFault.reason(error)) }

    /** Answers scan [id], once; an answer for an earlier scan is dropped. */
    private fun finish(id: Int, answer: (MethodChannel.Result) -> Unit) {
        activity.runOnUiThread {
            val result = pending
            if (id == attempt && result != null) {
                pending = null
                answer(result)
            }
        }
    }

    companion object {
        /**
         * How long the scanner may take to arrive before the scan is given
         * up: it is a few megabytes, so a minute and a half is ample on any
         * network that works.
         */
        const val FETCH_TIMEOUT_MS = 90_000L
    }
}
