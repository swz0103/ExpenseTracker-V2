package io.github.swz0103.expensetracker

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.PersistableBundle
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Copies a secret, such as the recovery code, flagged sensitive
 * (lib/src/app/android/clipboard_adapter.dart): Android 13 and later then
 * leave it out of the clipboard preview, and keyboards out of their
 * suggestions. The app takes it off the clipboard after a minute
 * (sensitive_clipboard.dart).
 */
class ClipboardHandler(private val activity: FragmentActivity) : ChannelHandler {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "copySensitive" -> {
                val text = call.argument<String>("text")
                val label = call.argument<String>("label")
                if (text == null || label == null) {
                    result.error("bad-arguments", "text and label are required", null)
                } else {
                    try {
                        copy(text, label)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("clipboard", e.message, null)
                    }
                }
            }
            else -> return false
        }
        return true
    }

    private fun copy(text: String, label: String) {
        val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText(label, text)
        // ClipDescription.EXTRA_IS_SENSITIVE (API 33); older phones read the
        // same key, as Android's own documentation advises.
        clip.description.extras = PersistableBundle().apply {
            putBoolean(IS_SENSITIVE, true)
        }
        clipboard.setPrimaryClip(clip)
    }

    private companion object {
        const val IS_SENSITIVE = "android.content.extra.IS_SENSITIVE"
    }
}
