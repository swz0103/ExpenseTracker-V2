package io.github.swz0103.expensetracker

import android.app.Activity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/**
 * One part of `expense_tracker/platform` (lib/src/app/android/): it
 * answers the methods it knows and leaves the rest to the next part.
 * Each part registers its activity results when it is made, which must be
 * while the activity itself is being made.
 */
interface ChannelHandler {
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

/**
 * The one way a handler works off the main thread (AND-07): [run] does the
 * work on a thread of its own and answers on the main thread, once, with
 * its value, or, whatever it throws (an `OutOfMemoryError` on a huge photo
 * included), with the failure named as [ScanFault.kind] names it, which the
 * app keeps in its error log (`PlatformException.details`). Nothing thrown
 * there can bring the app down.
 */
internal class OffMain(
    private val start: (Runnable) -> Unit,
    private val main: (Runnable) -> Unit,
) {
    /** Runs [work] off the main thread; [done] with its value, or [failed], on the main thread. */
    fun <T> run(work: () -> T, done: (T) -> Unit, failed: (Throwable) -> Unit) {
        start(
            Runnable {
                val answer = try {
                    val value = work()
                    Runnable { done(value) }
                } catch (e: Throwable) {
                    Runnable { failed(e) }
                }
                main(answer)
            },
        )
    }

    /** Runs [work] off the main thread and answers [result] on it; a failure as [code]. */
    fun <T> answer(result: MethodChannel.Result, code: String, work: () -> T) =
        run(work, { result.success(it) }, { result.error(code, it.message, kindOf(it)) })

    companion object {
        /** A thread of its own for the work, the activity's main thread for the answer. */
        fun of(activity: Activity) = OffMain({ Thread(it).start() }, activity::runOnUiThread)

        /**
         * One thread for the work, each piece after the one before, in the
         * order asked, for work two of which must not overlap (the
         * Keystore's keys, the reminders' plan); the thread goes when idle.
         */
        fun serial(activity: Activity): OffMain = serial(activity::runOnUiThread)

        /** [serial], answering through [main]. */
        fun serial(main: (Runnable) -> Unit): OffMain {
            val queue = ThreadPoolExecutor(0, 1, IDLE_SECONDS, TimeUnit.SECONDS, LinkedBlockingQueue())
            return OffMain(queue::execute, main)
        }

        /** How long the thread of [serial] waits for more work before it goes. */
        private const val IDLE_SECONDS = 30L

        /** What kind of failure [error] is, as the error log keeps it. */
        fun kindOf(error: Throwable): String = ScanFault.kind(error.javaClass.simpleName)
    }
}

