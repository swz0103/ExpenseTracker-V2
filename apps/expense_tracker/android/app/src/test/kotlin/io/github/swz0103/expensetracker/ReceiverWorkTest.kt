package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit

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
    fun theReceiversHaveThreadsOfTheirOwnThatALongHandlerJobLeavesFree() {
        // Review 34: the handlers' threads all busy, an alarm still runs.
        assertEquals(2, ReceiverWork.MOST_THREADS)
        assertEquals(ReceiverWork.MOST_THREADS, ReceiverWork.POOL.maximumPoolSize)
        assertNotSame(OffMain.POOL, ReceiverWork.POOL)
        val release = CountDownLatch(1)
        val busy = CountDownLatch(OffMain.MOST_THREADS)
        repeat(OffMain.MOST_THREADS) {
            OffMain.POOL.execute {
                busy.countDown()
                release.await(5, TimeUnit.SECONDS)
            }
        }
        try {
            assertTrue(busy.await(5, TimeUnit.SECONDS))
            val finished = CountDownLatch(1)
            ReceiverWork.run({ finished.countDown() }, ReceiverWork.POOL, { steps.add("work") }) { steps.add("failed") }
            assertTrue(finished.await(5, TimeUnit.SECONDS))
            assertEquals(listOf("work"), steps)
        } finally {
            release.countDown()
        }
    }

    @Test
    fun calledWithoutABroadcastTheWorkRunsInPlace() {
        // As a device test calls onReceive itself: goAsync gives nothing.
        ReceiverWork.run(null, pool, { steps.add("work") }) { steps.add("failed") }
        assertEquals(listOf("work"), steps)
    }
}
