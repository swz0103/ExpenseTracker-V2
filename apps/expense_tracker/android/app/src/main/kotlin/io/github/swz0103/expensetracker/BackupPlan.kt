package io.github.swz0103.expensetracker

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * The rules the background job (BackupWorker.kt) follows, the same as the
 * app's own (phone_backup.dart, drive_sync.dart); kept apart from Android
 * so they are tested on their own.
 */
internal object BackupPlan {
    const val DAY = 24L * 60 * 60 * 1000

    /** How many of a ledger's backups stay in the phone's folder and on Drive. */
    const val KEEP = 5

    /**
     * Whether a backup of [revision] is due at [now]: none was made yet,
     * or the last one, at [last] of [lastRevision], is at least [every]
     * old and the ledger changed since.
     */
    fun due(now: Long, last: Long?, lastRevision: Int?, revision: Int, every: Long): Boolean =
        last == null || (now - last >= every && lastRevision != revision)

    /**
     * Milliseconds of a time as Dart writes it in preferences.json
     * (`2026-10-28T03:04:05.123Z`, in UTC); null when there is none.
     */
    fun millisOf(text: String?): Long? {
        if (text == null || text.length < 19) return null
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.ROOT)
        format.timeZone = TimeZone.getTimeZone("UTC")
        val whole = try {
            format.parse(text.substring(0, 19))?.time
        } catch (e: java.text.ParseException) {
            null
        } ?: return null
        val fraction = Regex("^\\.(\\d{1,3})").find(text.substring(19))?.groupValues?.get(1)
        return whole + (fraction?.padEnd(3, '0')?.toLong() ?: 0)
    }

    /**
     * The name of a backup of the ledger marked [mark] taken at [at] in
     * the phone's folder: `記帳本-<mark>-YYYYMMDD-HHMM.etbk`, as
     * PhoneBackup.nameAt writes it.
     */
    fun phoneName(mark: String, at: Long, zone: TimeZone = TimeZone.getDefault()): String {
        val time = Calendar.getInstance(zone).apply { timeInMillis = at }
        fun two(n: Int) = n.toString().padStart(2, '0')
        return "記帳本-$mark-${time.get(Calendar.YEAR)}${two(time.get(Calendar.MONTH) + 1)}" +
            "${two(time.get(Calendar.DAY_OF_MONTH))}-${two(time.get(Calendar.HOUR_OF_DAY))}" +
            "${two(time.get(Calendar.MINUTE))}.etbk"
    }

    /**
     * Of the names in the phone's folder, those of the ledger marked
     * [mark] beyond the newest [KEEP]; other files, and other ledgers'
     * backups, are never among them.
     */
    fun beyondKept(names: List<String>, mark: String): List<String> =
        names.filter { it.startsWith("記帳本-$mark-") && it.endsWith(".etbk") }
            .sortedDescending()
            .drop(KEEP)
}
