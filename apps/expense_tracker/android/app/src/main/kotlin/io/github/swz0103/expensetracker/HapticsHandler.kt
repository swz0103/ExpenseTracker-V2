package io.github.swz0103.expensetracker

import android.content.Context
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The small vibrations of the app's taps (lib/src/app/android/haptics_adapter.dart):
 * Android's own tick, click and heavy click, which phones tune for the
 * hand, rather than Flutter's, whose lightest is a clock's tick too faint
 * to feel on many phones. They are touch vibrations, so turning touch
 * vibration off in the phone's settings stops them as well.
 */
class HapticsHandler(private val activity: FragmentActivity) : ChannelHandler {
    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= 31) {
            (activity.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            activity.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != "haptic") return false
        val vibrator = vibrator
        if (vibrator != null && vibrator.hasVibrator()) {
            vibrate(vibrator, HapticKind.of(call.argument<String>("kind")))
        }
        result.success(null)
        return true
    }

    private fun vibrate(vibrator: Vibrator, kind: HapticKind) {
        val effect = if (Build.VERSION.SDK_INT >= 29) {
            VibrationEffect.createPredefined(kind.predefined)
        } else {
            VibrationEffect.createOneShot(kind.millis, VibrationEffect.DEFAULT_AMPLITUDE)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(effect)
        }
    }
}

/** A tap's weight: Android's predefined effect, or how long to buzz on
 *  phones before Android 10, which have none. */
internal enum class HapticKind(val predefined: Int, val millis: Long) {
    TICK(VibrationEffect.EFFECT_TICK, 10),
    CLICK(VibrationEffect.EFFECT_CLICK, 20),
    HEAVY(VibrationEffect.EFFECT_HEAVY_CLICK, 35);

    companion object {
        /** The kind the app names; a click for anything else. */
        fun of(name: String?): HapticKind = when (name) {
            "tick" -> TICK
            "heavy" -> HEAVY
            else -> CLICK
        }
    }
}
