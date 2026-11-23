package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Test

/** The window is hidden from screenshots unless the app plainly says not to. */
class LockWindowTest {
    @Test
    fun theWindowIsHiddenUntilTheAppSaysOtherwise() {
        // Nothing said yet, as when the activity is made.
        assertEquals(true, LockWindow.wanted(null))
        assertEquals(true, LockWindow.wanted(true))
    }

    @Test
    fun onlyAPlainNoShowsTheWindow() {
        assertEquals(false, LockWindow.wanted(false))
    }

    @Test
    fun uptimeNamesThisStartOfThePhone() {
        assertEquals(
            mapOf("boot" to "boot-12", "upMs" to 90_000L),
            LockWindow.uptime(12, 90_000L),
        )
    }

    @Test
    fun aPhoneThatDoesNotCountItsStartsGivesNoName() {
        assertEquals(
            mapOf<String, Any?>("boot" to null, "upMs" to 90_000L),
            LockWindow.uptime(-1, 90_000L),
        )
    }
}
