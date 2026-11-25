package io.github.swz0103.expensetracker

import android.content.BroadcastReceiver
import android.util.Log
import java.util.concurrent.Executor

/**
 * How a receiver does its Keystore and file work: off the main thread,
 * with [BroadcastReceiver.goAsync] keeping the broadcast open until the
 * work ends, so an alarm or a tap on 「確認入帳」 never holds the main
 * thread while a key opens or a file is written (review 32).
 */
internal object ReceiverWork {
    private const val TAG = "ReceiverWork"

    /** Runs [work] for [receiver] on [OffMain.POOL]. */
    fun of(receiver: BroadcastReceiver, work: () -> Unit) {
        // Null when the receiver is called directly rather than by a
        // broadcast (a device test): the work then runs in place.
        val pending: BroadcastReceiver.PendingResult? = receiver.goAsync()
        run(pending?.let { it::finish }, OffMain.POOL, work) {
            Log.w(TAG, "receiver work failed: ${it.javaClass.simpleName}")
        }
    }

    /**
     * Runs [work] on [executor] and then [finish]es, whatever the work
     * throws (a failure goes to [failed]); in place when there is nothing to [finish], as nothing
     * then keeps the broadcast open for it.
     */
    fun run(finish: (() -> Unit)?, executor: Executor, work: () -> Unit, failed: (Exception) -> Unit) {
        if (finish == null) {
            work()
            return
        }
        executor.execute {
            try {
                work()
            } catch (e: Exception) {
                // Nothing waits for an answer: the next alarm or the app
                // opened arms the plan again.
                failed(e)
            } finally {
                finish()
            }
        }
    }
}
