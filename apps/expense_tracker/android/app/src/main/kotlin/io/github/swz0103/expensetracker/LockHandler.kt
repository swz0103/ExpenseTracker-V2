package io.github.swz0103.expensetracker

import android.os.SystemClock
import android.provider.Settings
import android.view.Window
import android.view.WindowManager
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The phone's part of the app's lock gate (lib/src/core/platform/lock_gate.dart,
 * lib/src/app/android/lock_adapter.dart): keeping the window out of
 * screenshots, putting the app behind the others without closing it, and a
 * clock no setting moves for the wait after wrong passwords. The app decides
 * all of it; this only does what it is told.
 */
class LockHandler(private val activity: FragmentActivity) : ChannelHandler {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "secureScreen" -> {
                LockWindow.secure(activity.window, LockWindow.wanted(call.argument<Boolean>("on")))
                result.success(null)
            }
            // Back on the first screen: the app stays open behind the others,
            // as after the home button, so its ledger is not closed.
            "moveToBack" -> {
                activity.moveTaskToBack(true)
                result.success(null)
            }
            "uptime" -> result.success(
                LockWindow.uptime(
                    Settings.Global.getInt(activity.contentResolver, Settings.Global.BOOT_COUNT, -1),
                    SystemClock.elapsedRealtime(),
                ),
            )
            else -> return false
        }
        return true
    }
}

/** What [LockHandler] works out, kept apart from Android to be tested. */
internal object LockWindow {
    /**
     * Whether the window is kept out of screenshots, recordings and the
     * recent apps list for what the app asked: always, unless it plainly
     * says not to. So is it from the moment the activity is made
     * ([MainActivity.onCreate]), before the app has said anything: the first
     * thing shown is the lock screen.
     */
    fun wanted(asked: Boolean?): Boolean = asked != false

    /** Sets or clears `FLAG_SECURE` on [window]. */
    fun secure(window: Window, on: Boolean) {
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    /**
     * How long the phone has run since it started, sleep included
     * ([elapsedMs]), with a name for that start made of its count of starts
     * ([bootCount]); no name when the phone does not tell the count (below
     * zero), and the app then goes by the wall clock.
     */
    fun uptime(bootCount: Int, elapsedMs: Long): Map<String, Any?> = mapOf(
        "boot" to if (bootCount < 0) null else "boot-$bootCount",
        "upMs" to elapsedMs,
    )
}
