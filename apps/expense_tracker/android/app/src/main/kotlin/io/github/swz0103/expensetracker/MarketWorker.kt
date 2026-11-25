package io.github.swz0103.expensetracker

import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Fetches the exchanges' day lists and the bank's rates every few hours,
 * without the app being opened, so the closes are on the phone before
 * 投資 is: the app reads them from `files/market/` when they are fresh
 * (lib/src/app/android/market_cache_adapter.dart) and asks the network only when
 * they are not. The addresses are the ones the app wrote in `urls.txt`, a line each:
 * a file name, an address, and when the kept copy goes stale, as the app
 * decides it ([MarketCache.Entry]); a copy not stale yet is left as it is,
 * so nights and weekends cost nothing past what the app's rule asks.
 * Only the three public hosts are fetched, and nothing of the ledger is
 * read or sent. The app lists only what the ledger needs (the exchanges'
 * lists while shares are held, the bank's rates while an account is in
 * another currency) and stops the job when it needs neither; it runs on
 * any network, never on a low battery, and a run the network cut short is
 * tried again after a growing wait ([BackgroundWork]; AND-05).
 */
class MarketWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val dir = File(applicationContext.filesDir, "market")
        val list = File(dir, "urls.txt")
        if (!list.exists()) return Result.success()
        var cut: IOException? = null
        val now = System.currentTimeMillis()
        for (line in list.readLines()) {
            val entry = MarketCache.entry(line) ?: continue
            val target = File(dir, "${entry.name}.txt")
            val modified = if (target.exists()) target.lastModified() else null
            if (!entry.stale(modified, now)) continue
            try {
                val body = fetch(URL(entry.address)) ?: continue
                // Its own name beside the app's (market_cache_adapter.dart),
                // so the two never write into one half-written file.
                val partial = File(dir, target.name + MarketCache.PART_SUFFIX)
                partial.writeText(body)
                partial.renameTo(target)
            } catch (e: IOException) {
                cut = e
            } catch (e: Exception) {
                // The app asks again when it opens.
            }
        }
        val failed = cut ?: return Result.success()
        // The network went away: tried again after a growing wait, a few
        // times; then the app asks again when it opens.
        return if (BackgroundWork.retries(failed, runAttemptCount)) Result.retry() else Result.success()
    }

    private fun fetch(url: URL): String? {
        val connection = url.openConnection() as HttpURLConnection
        connection.connectTimeout = 20_000
        connection.readTimeout = 30_000
        connection.instanceFollowRedirects = false
        connection.setRequestProperty("Accept", "application/json, text/csv")
        connection.setRequestProperty("User-Agent", "ExpenseTracker-V2")
        return try {
            if (connection.responseCode != 200) return null
            connection.inputStream.bufferedReader().use { MarketCache.readCapped(it) }
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        private const val NAME = "market"

        /**
         * Every three hours on any network from now on, or stopped with [on]
         * false (lib/src/app/android/market_cache_adapter.dart).
         */
        fun schedule(context: Context, on: Boolean) {
            val work = WorkManager.getInstance(context)
            if (!on) {
                work.cancelUniqueWork(NAME)
                return
            }
            val request = BackgroundWork.periodic(MarketWorker::class.java, 3, BackgroundWork.MARKET_NETWORK)
            // UPDATE: a job scheduled by an earlier version takes the
            // constraints of this one, keeping its place in time.
            work.enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
        }
    }
}

/** The cache's rules, kept apart from Android to be tested. */
internal object MarketCache {
    /** The same cap as the app's transport, in characters. */
    const val LIMIT = 8 * 1024 * 1024

    /** The job's half-written copy; the app's has its own (`.app.part`). */
    const val PART_SUFFIX = ".worker.part"

    /**
     * All of [reader], or null once it is longer than [limit] characters:
     * read a piece at a time, so a body past the cap is never held whole.
     */
    fun readCapped(reader: java.io.Reader, limit: Int = LIMIT): String? {
        val text = StringBuilder()
        val buffer = CharArray(16 * 1024)
        while (true) {
            val read = reader.read(buffer)
            if (read < 0) return text.toString()
            if (text.length + read > limit) return null
            text.appendRange(buffer, 0, read)
        }
    }

    /**
     * A line of `urls.txt`: the file [name], its [address], and when the
     * kept copy goes stale, as the app decides it: older than [maxAge]
     * milliseconds, or kept before one of the [checkpoints] (instants in
     * ms) that has come. Without them (a list of an older version) it
     * is always fetched.
     */
    data class Entry(
        val name: String,
        val address: String,
        val maxAge: Long? = null,
        val checkpoints: List<Long> = emptyList(),
    ) {
        /** Whether a copy changed last at [modified] (null: none) is to be fetched again at [now]. */
        fun stale(modified: Long?, now: Long): Boolean {
            if (modified == null || maxAge == null) return true
            // A clock set back: the copy's age is unknown.
            if (modified > now) return true
            if (now - modified >= maxAge) return true
            return checkpoints.any { it in (modified + 1)..now }
        }
    }

    private val hosts = setOf("openapi.twse.com.tw", "www.tpex.org.tw", "rate.bot.com.tw")

    /** Only https to the three hosts the app reads closes and rates from. */
    fun allowed(address: String): Boolean = try {
        val url = URL(address)
        url.protocol == "https" && url.host in hosts
    } catch (e: Exception) {
        false
    }

    private val names = setOf("twse", "tpex", "rates")

    /**
     * A line of `urls.txt` (name, address, and, from the app's version
     * that decides it, the most age and the checkpoints, by tabs; the
     * checkpoints by commas); null for one that is not a known name and an
     * allowed address, or whose times are not numbers.
     */
    fun entry(line: String): Entry? {
        // Spaces and a CR around it go; not tabs, as the last field may be empty.
        val parts = line.trim(' ', '\r').split('\t')
        if (parts.size != 2 && parts.size != 4) return null
        if (parts[0] !in names || !allowed(parts[1])) return null
        if (parts.size == 2) return Entry(parts[0], parts[1])
        val maxAge = parts[2].toLongOrNull()?.takeIf { it > 0 } ?: return null
        val checkpoints = if (parts[3].isEmpty()) {
            emptyList()
        } else {
            parts[3].split(',').map { it.toLongOrNull() ?: return null }
        }
        return Entry(parts[0], parts[1], maxAge, checkpoints)
    }
}
