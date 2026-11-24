package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.StringReader

class MarketCacheTest {
    private val hour = 3_600_000L

    /** 2026-11-16 06:30 UTC, 14:30 in Taipei: a day's close. */
    private val close = 1_794_810_600_000L

    @Test
    fun aKnownNameAndHostIsFetched() {
        val line = "twse\thttps://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL"
        assertEquals("twse", MarketCache.entry(line)?.name)
    }

    @Test
    fun anyOtherNameOrHostIsNot() {
        assertNull(MarketCache.entry("ledger\thttps://openapi.twse.com.tw/x"))
        assertNull(MarketCache.entry("twse\thttps://example.com/x"))
        assertNull(MarketCache.entry("twse\thttp://openapi.twse.com.tw/x"))
    }

    @Test
    fun theAppsStaleRuleIsReadFromItsLine() {
        // Review 21 finding 6: 12 hours (43,200,000 ms) and two closes a
        // day apart (1,794,810,600,000 + 86,400,000 = 1,794,897,000,000).
        val line = "twse\thttps://openapi.twse.com.tw/x\t43200000\t1794810600000,1794897000000"
        assertEquals(
            MarketCache.Entry(
                "twse",
                "https://openapi.twse.com.tw/x",
                43_200_000L,
                listOf(1_794_810_600_000L, 1_794_897_000_000L),
            ),
            MarketCache.entry(line),
        )
        // The bank's rates: three hours (10,800,000 ms), no checkpoints.
        assertEquals(
            MarketCache.Entry("rates", "https://rate.bot.com.tw/x", 10_800_000L),
            MarketCache.entry("rates\thttps://rate.bot.com.tw/x\t10800000\t"),
        )
        assertNull(MarketCache.entry("twse\thttps://openapi.twse.com.tw/x\tsoon\t"))
        assertNull(MarketCache.entry("twse\thttps://openapi.twse.com.tw/x\t43200000\t1,x"))
        assertNull(MarketCache.entry("twse\thttps://openapi.twse.com.tw/x\t0\t"))
    }

    @Test
    fun aCopyIsFetchedOnlyWhenTheAppsRuleSaysItIsStale() {
        val entry = MarketCache.Entry("twse", "https://openapi.twse.com.tw/x", 12 * hour, listOf(close))
        // None kept yet.
        assertTrue(entry.stale(null, close))
        // Kept an hour after the close, asked at night: still the close's.
        assertFalse(entry.stale(close + hour, close + 6 * hour))
        // Twelve hours old: stale.
        assertTrue(entry.stale(close + hour, close + 13 * hour))
        // Kept before the close, asked after it: stale.
        assertTrue(entry.stale(close - hour, close + 1))
        // Kept before the close, asked before it: still fresh.
        assertFalse(entry.stale(close - 2 * hour, close - hour))
        // Kept at the close itself: the close's.
        assertFalse(entry.stale(close, close + hour))
        // A clock set back: unknown, fetched.
        assertTrue(entry.stale(close + hour, close))
    }

    @Test
    fun aLineOfAnOlderVersionIsAlwaysFetched() {
        val entry = MarketCache.entry("twse\thttps://openapi.twse.com.tw/x")!!
        assertTrue(entry.stale(close, close + 1))
    }

    @Test
    fun aBodyPastTheCapIsNotHeldWhole() {
        assertEquals("abcde", MarketCache.readCapped(StringReader("abcde"), limit = 5))
        assertNull(MarketCache.readCapped(StringReader("abcdef"), limit = 5))
        // The real cap: 8 MiB of characters, 8 * 1024 * 1024.
        assertEquals(8_388_608, MarketCache.LIMIT)
    }

    @Test
    fun theJobAndTheAppWriteApart() {
        // market_cache_adapter.dart writes `.app.part`.
        assertEquals(".worker.part", MarketCache.PART_SUFFIX)
    }
}
