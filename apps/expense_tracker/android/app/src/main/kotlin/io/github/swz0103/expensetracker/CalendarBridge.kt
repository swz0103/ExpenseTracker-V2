package io.github.swz0103.expensetracker

import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
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
     */
    fun replace(
        resolver: ContentResolver,
        calendar: Long,
        from: Long,
        events: List<Map<String, Any?>>,
    ): Int {
        resolver.delete(
            Events.CONTENT_URI,
            "${Events.CALENDAR_ID} = ? AND ${Events.DTSTART} >= ? AND ${Events.DESCRIPTION} LIKE ?",
            arrayOf(calendar.toString(), from.toString(), "%$MARK%"),
        )
        var written = 0
        for (event in events) {
            val start = (event["start"] as? Number)?.toLong() ?: continue
            val values = ContentValues().apply {
                put(Events.CALENDAR_ID, calendar)
                put(Events.TITLE, event["title"] as? String ?: "")
                put(Events.DESCRIPTION, "${event["note"] as? String ?: ""}\n$MARK${event["key"]}")
                put(Events.DTSTART, start)
                put(Events.DTEND, start + 30 * MINUTE)
                put(Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                put(Events.HAS_ALARM, 1)
            }
            val uri = resolver.insert(Events.CONTENT_URI, values) ?: continue
            val id = ContentUris.parseId(uri)
            val minutes = (event["remind"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() }
                ?: listOf(0)
            for (before in minutes) {
                resolver.insert(
                    Reminders.CONTENT_URI,
                    ContentValues().apply {
                        put(Reminders.EVENT_ID, id)
                        put(Reminders.MINUTES, before)
                        put(Reminders.METHOD, Reminders.METHOD_ALERT)
                    },
                )
            }
            written++
        }
        return written
    }
}
