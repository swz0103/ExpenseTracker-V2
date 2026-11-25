package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.concurrent.Executor

/** Review 32: a receiver's Keystore and file work runs off the main thread, and the broadcast always ends. */
class ReceiverWorkTest {
    private val steps = mutableListOf<String>()

    /** The pool, played in place: what it runs is noted as run there. */
    private val pool = Executor { steps.add("pool"); it.run() }

    @Test
    fun theWorkRunsOnThePoolAndTheBroadcastEndsAfter() {
        ReceiverWork.run({ steps.add("finish") }, pool, { steps.add("work") }) { steps.add("failed") }
        assertEquals(listOf("pool", "work", "finish"), steps)
    }

    @Test
    fun aFailureStillEndsTheBroadcast() {
        ReceiverWork.run(
            { steps.add("finish") },
            pool,
            { throw IllegalStateException("key gone") },
        ) { steps.add("failed ${it.javaClass.simpleName}") }
        assertEquals(listOf("pool", "failed IllegalStateException", "finish"), steps)
    }

    @Test
    fun calledWithoutABroadcastTheWorkRunsInPlace() {
        // As a device test calls onReceive itself: goAsync gives nothing.
        ReceiverWork.run(null, pool, { steps.add("work") }) { steps.add("failed") }
        assertEquals(listOf("work"), steps)
    }
}
