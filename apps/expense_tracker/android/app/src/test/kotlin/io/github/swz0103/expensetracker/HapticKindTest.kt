package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Test

class HapticKindTest {
    @Test
    fun readsTheKindTheAppNames() {
        assertEquals(HapticKind.TICK, HapticKind.of("tick"))
        assertEquals(HapticKind.CLICK, HapticKind.of("click"))
        assertEquals(HapticKind.HEAVY, HapticKind.of("heavy"))
        assertEquals(HapticKind.CLICK, HapticKind.of(null))
        assertEquals(HapticKind.CLICK, HapticKind.of("thud"))
    }
}
