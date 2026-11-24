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
 * they are not. The addresses are the ones the app wrote in `urls.txt`,
 * a file name and an address a line;
 * only the three public hosts are fetched, and nothing of the ledger is
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
        for (line in list.readLines()) {
            val (name, address) = MarketCache.entry(line) ?: continue
            try {
                val body = fetch(URL(address)) ?: continue
                val target = File(dir, "$name.txt")
                val partial = File(dir, target.name + ".part")
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
            val text = connection.inputStream.bufferedReader().use { it.readText() }
            if (text.length > MarketCache.LIMIT) null else text
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

    private val hosts = setOf("openapi.twse.com.tw", "www.tpex.org.tw", "rate.bot.com.tw")

    /** Only https to the three hosts the app reads closes and rates from. */
    fun allowed(address: String): Boolean = try {
        val url = URL(address)
        url.protocol == "https" && url.host in hosts
    } catch (e: Exception) {
        false
    }

    private val names = setOf("twse", "tpex", "rates")

    /** A line of `urls.txt` as its file name and address; null for one
     *  that is not a known name and an allowed address. */
    fun entry(line: String): Pair<String, String>? {
        val parts = line.trim().split('\t')
        if (parts.size != 2 || parts[0] !in names || !allowed(parts[1])) return null
        return parts[0] to parts[1]
    }
}
