package io.github.swz0103.expensetracker

import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Starts or stops the background jobs: the one that delivers the backups
 * left in the outbox (BackupWorker.kt;
 * lib/src/app/android/background_backup_adapter.dart), and the one that
 * fetches the market's lists while the ledger needs them (MarketWorker.kt;
 * lib/src/app/android/market_cache_adapter.dart).
 */
class BackupsHandler(private val activity: FragmentActivity) : ChannelHandler {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        val schedule: (Boolean) -> Unit = when (call.method) {
            "backgroundBackups" -> { on -> BackupWorker.schedule(activity.applicationContext, on) }
            "marketJob" -> { on -> MarketWorker.schedule(activity.applicationContext, on) }
            else -> return false
        }
        try {
            schedule(call.argument<Boolean>("on") == true)
            result.success(null)
        } catch (e: Exception) {
            result.error("backups", e.message, ScanFault.kind(e.javaClass.simpleName))
        }
        return true
    }
}
