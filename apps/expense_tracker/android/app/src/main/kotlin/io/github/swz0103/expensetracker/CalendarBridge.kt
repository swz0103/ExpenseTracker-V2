package io.github.swz0103.expensetracker

import android.content.ContentProviderOperation
import android.content.ContentResolver
import android.content.ContentValues
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Reminders
import java.util.TimeZone

/**
 * Writes the ledger's due dates into a calendar the person picks, such as
 * their Google Calendar, so its own reminders tell them. The app's events
 * carry [MARK] in their description; a sync replaces the ones still to
 * come and leaves past ones alone.
 */
object CalendarBridge {
    private const val MARK = "記帳本#"
    private const val MINUTE = 60_000L
    /** Below the provider's 500 operations per transaction, with room to spare. */
    private const val MAX_OPERATIONS = 450

    /** Calendars the app may write to: id, name and the account they sync with. */
    fun calendars(resolver: ContentResolver): List<Map<String, Any>> {
        val projection = arrayOf(
            Calendars._ID,
            Calendars.CALENDAR_DISPLAY_NAME,
            Calendars.ACCOUNT_NAME,
            Calendars.CALENDAR_ACCESS_LEVEL,
        )
        val found = mutableListOf<Map<String, Any>>()
        resolver.query(Calendars.CONTENT_URI, projection, null, null, null)?.use { row ->
            while (row.moveToNext()) {
                if (row.getInt(3) < Calendars.CAL_ACCESS_CONTRIBUTOR) continue
                found.add(
                    mapOf(
                        "id" to row.getLong(0),
                        "name" to (row.getString(1) ?: ""),
                        "account" to (row.getString(2) ?: ""),
                    ),
                )
            }
        }
        return found
    }

    /**
     * Replaces the app's events from [from] on in [calendar] with [events]:
     * each has a key, title, note, start (milliseconds) and minutes to remind
     * before it. Returns how many were written.
     *
     * The removal and the new events go in one batch with no yield points,
     * which the calendar provider applies in one transaction: a failure
     * part way leaves the calendar as it was, rather than without its
     * events or with them twice. The provider refuses a batch of 500
     * operations or more without a yield point, and a yield point would
     * commit what came before it, so instead the batch is kept under
     * [MAX_OPERATIONS]: [events] come soonest first, and those that do not
     * fit (the furthest away) are left out until a later sync, when they
     * are nearer and the earlier ones have passed.
     */
    fun replace(
        resolver: ContentResolver,
        calendar: Long,
        from: Long,
        events: List<Map<String, Any?>>,
    ): Int {
        val ops = ArrayList<ContentProviderOperation>()
        // Only the app's own events: the mark starts the last line of the
        // description, as written below, not anywhere in someone's note.
        ops.add(
            ContentProviderOperation.newDelete(Events.CONTENT_URI)
                .withSelection(
                    "${Events.CALENDAR_ID} = ? AND ${Events.DTSTART} >= ? AND " +
                        "${Events.DESCRIPTION} LIKE ? AND ${Events.DESCRIPTION} NOT LIKE ?",
                    arrayOf(calendar.toString(), from.toString(), "%\n$MARK%", "%\n$MARK%\n%"),
                )
                .build(),
        )
        var written = 0
        for (event in events) {
            val start = (event["start"] as? Number)?.toLong() ?: continue
            val minutes = (event["remind"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() }
                ?: listOf(0)
            // One insert for the event and one per reminder; stop before the
            // batch grows too large for one transaction.
            if (ops.size + 1 + minutes.size > MAX_OPERATIONS) break
            val values = ContentValues().apply {
                put(Events.CALENDAR_ID, calendar)
                put(Events.TITLE, event["title"] as? String ?: "")
                put(Events.DESCRIPTION, "${event["note"] as? String ?: ""}\n$MARK${event["key"]}")
                put(Events.DTSTART, start)
                put(Events.DTEND, start + 30 * MINUTE)
                put(Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                // Only an event with reminders rings.
                put(Events.HAS_ALARM, if (minutes.isEmpty()) 0 else 1)
            }
            val eventAt = ops.size
            ops.add(
                ContentProviderOperation.newInsert(Events.CONTENT_URI)
                    .withValues(values)
                    .build(),
            )
            for (before in minutes) {
                ops.add(
                    ContentProviderOperation.newInsert(Reminders.CONTENT_URI)
                        .withValues(
                            ContentValues().apply {
                                put(Reminders.MINUTES, before)
                                put(Reminders.METHOD, Reminders.METHOD_ALERT)
                            },
                        )
                        // The id of the event inserted just before.
                        .withValueBackReference(Reminders.EVENT_ID, eventAt)
                        .build(),
                )
            }
            written++
        }
        resolver.applyBatch(CalendarContract.AUTHORITY, ops)
        return written
    }
}
