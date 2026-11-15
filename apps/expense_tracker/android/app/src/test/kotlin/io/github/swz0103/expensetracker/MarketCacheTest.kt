package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MarketCacheTest {
    @Test
    fun aKnownNameAndHostIsFetched() {
        val line = "twse\thttps://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL"
        assertEquals("twse", MarketCache.entry(line)?.first)
    }

    @Test
    fun anyOtherNameOrHostIsNot() {
        assertNull(MarketCache.entry("ledger\thttps://openapi.twse.com.tw/x"))
        assertNull(MarketCache.entry("twse\thttps://example.com/x"))
        assertNull(MarketCache.entry("twse\thttp://openapi.twse.com.tw/x"))
    }
}
