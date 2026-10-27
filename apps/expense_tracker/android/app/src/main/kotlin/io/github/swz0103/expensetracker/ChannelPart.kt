package io.github.swz0103.expensetracker

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * One part of `expense_tracker/platform` (lib/src/app/android/): it
 * answers the methods it knows and leaves the rest to the next part.
 * Each part registers its activity results when it is made, which must be
 * while the activity itself is being made.
 */
interface ChannelPart {
    /** Answers [call] and returns true, or returns false when not its own. */
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean
}

/**
 * Starts another app's screen for [result]; when none can be started
 * (no camera app, the file chooser turned off), [clear]s what waits for
 * it and says so, so the next try is not refused as busy.
 */
internal inline fun launchOr(
    result: MethodChannel.Result,
    clear: () -> Unit,
    start: () -> Unit,
) {
    try {
        start()
    } catch (e: Exception) {
        clear()
        result.error("unavailable", e.message ?: "No app can do this.", null)
    }
}
