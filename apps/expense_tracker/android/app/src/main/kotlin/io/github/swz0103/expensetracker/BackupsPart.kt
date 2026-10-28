package io.github.swz0103.expensetracker

import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Starts or stops the background job that delivers the backups left in
 * the outbox (BackupWorker.kt; lib/src/app/android/backups.dart).
 */
class BackupsPart(private val activity: FragmentActivity) : ChannelPart {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != "backgroundBackups") return false
        try {
            BackupWorker.schedule(activity.applicationContext, call.argument<Boolean>("on") == true)
            result.success(null)
        } catch (e: Exception) {
            result.error("backups", e.message, null)
        }
        return true
    }
}
