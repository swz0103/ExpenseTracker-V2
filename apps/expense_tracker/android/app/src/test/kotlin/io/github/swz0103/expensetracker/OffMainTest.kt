package io.github.swz0103.expensetracker

import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Test

/** AND-07: the one way off the main thread, and every failure answered. */
class OffMainTest {
    /** The threads, played in order: the work, then the answer. */
    private val steps = mutableListOf<String>()
    private val offMain = OffMain(
        { steps.add("work thread"); it.run() },
        { steps.add("main thread"); it.run() },
    )

    private class Answers : MethodChannel.Result {
        val said = mutableListOf<String>()
        override fun success(result: Any?) {
            said.add("success $result")
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            said.add("error $errorCode $errorMessage $errorDetails")
        }

        override fun notImplemented() {
            said.add("notImplemented")
        }
    }

    @Test
    fun theValueIsAnsweredOnTheMainThreadOnce() {
        val answers = Answers()
        offMain.answer(answers, "folder") { steps.add("work"); 42 }
        assertEquals(listOf("work thread", "work", "main thread"), steps)
        assertEquals(listOf("success 42"), answers.said)
    }

    @Test
    fun anExceptionIsAnsweredWithItsKind() {
        val answers = Answers()
        offMain.answer(answers, "export") { throw IllegalStateException("The chosen place cannot be written.") }
        assertEquals(
            listOf("error export The chosen place cannot be written. ILLEGAL_STATE_EXCEPTION"),
            answers.said,
        )
    }

    @Test
    fun anErrorSuchAsOutOfMemoryIsAnsweredNotThrown() {
        val answers = Answers()
        offMain.answer(answers, "calendar") { throw OutOfMemoryError("big") }
        assertEquals(listOf("error calendar big OUT_OF_MEMORY_ERROR"), answers.said)
    }

    @Test
    fun runHandsTheValueOrTheFailureToItsOwnAnswers() {
        val heard = mutableListOf<String>()
        offMain.run({ "ready.jpg" }, { heard.add("done $it") }, { heard.add("failed $it") })
        offMain.run({ throw StackOverflowError() }, { heard.add("done $it") }, { heard.add("failed ${OffMain.kindOf(it)}") })
        assertEquals(listOf("done ready.jpg", "failed STACK_OVERFLOW_ERROR"), heard)
    }
}
