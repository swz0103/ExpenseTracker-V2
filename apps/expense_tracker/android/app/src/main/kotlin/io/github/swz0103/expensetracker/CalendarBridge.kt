package io.github.swz0103.expensetracker

import android.accounts.Account
import android.content.ContentProviderOperation
import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.os.Bundle
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Reminders
import java.util.TimeZone

/**
 * Writes the ledger's due dates into a calendar the person picks, such as
 * their Google Calendar, so its own reminders tell them. The app decides
 * which events there should be and what changes (calendar_sync.dart);
 * this reads the app's events back and makes the changes it is given.
 * The app's events carry [MARK] and their key on the last line of their
 * description, which is how they are told apart from the person's own.
 */
object CalendarBridge {
    private const val MARK = "記帳本#"
    private const val MINUTE = 60_000L

    /** How long each event lasts. */
    private const val LENGTH = 30 * MINUTE

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

    /** A description as written: the note, then the mark and the key. */
    fun describe(note: String, key: String): String = "$note\n$MARK$key"

    /**
     * The note and key of an app's event from its [description]; null for
     * an event that is not the app's (no mark starting its last line).
     */
    fun split(description: String?): Pair<String, String>? {
        if (description == null) return null
        val at = description.lastIndexOf("\n$MARK")
        if (at < 0) return null
        val key = description.substring(at + 1 + MARK.length)
        if (key.contains('\n')) return null
        return description.substring(0, at) to key
    }

    /**
     * The app's events in [calendar] from [from] (milliseconds) on: the
     * calendar's id, key, title, note, start and minutes of reminders.
     */
    fun events(resolver: ContentResolver, calendar: Long, from: Long): List<Map<String, Any>> {
        val found = mutableListOf<Map<String, Any>>()
        resolver.query(
            Events.CONTENT_URI,
            arrayOf(Events._ID, Events.TITLE, Events.DESCRIPTION, Events.DTSTART),
            // Only the app's own events, not one deleted and waiting to sync.
            "${Events.CALENDAR_ID} = ? AND ${Events.DTSTART} >= ? AND " +
                "${Events.DELETED} = 0 AND ${Events.DESCRIPTION} LIKE ?",
            arrayOf(calendar.toString(), from.toString(), "%\n$MARK%"),
            null,
        )?.use { row ->
            while (row.moveToNext()) {
                val (note, key) = split(row.getString(2)) ?: continue
                val id = row.getLong(0)
                found.add(
                    mapOf(
                        "id" to id,
                        "key" to key,
                        "title" to (row.getString(1) ?: ""),
                        "note" to note,
                        "start" to row.getLong(3),
                        "remind" to remindersOf(resolver, id),
                    ),
                )
            }
        }
        return found
    }

    private fun remindersOf(resolver: ContentResolver, event: Long): List<Int> {
        val minutes = mutableListOf<Int>()
        Reminders.query(resolver, event, arrayOf(Reminders.MINUTES))?.use { row ->
            while (row.moveToNext()) minutes.add(row.getInt(0))
        }
        return minutes
    }

    private fun values(calendar: Long, event: Map<String, Any?>, start: Long, minutes: List<Int>) =
        ContentValues().apply {
            put(Events.CALENDAR_ID, calendar)
            put(Events.TITLE, event["title"] as? String ?: "")
            put(Events.DESCRIPTION, describe(event["note"] as? String ?: "", "${event["key"]}"))
            put(Events.DTSTART, start)
            put(Events.DTEND, start + LENGTH)
            put(Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            // Only an event with reminders rings.
            put(Events.HAS_ALARM, if (minutes.isEmpty()) 0 else 1)
        }

    private fun minutesOf(event: Map<String, Any?>): List<Int> =
        (event["remind"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() } ?: listOf(0)

    private fun reminder(minutes: Int): ContentValues = ContentValues().apply {
        put(Reminders.MINUTES, minutes)
        put(Reminders.METHOD, Reminders.METHOD_ALERT)
    }

    /**
     * Makes the changes the app worked out in [calendar]: takes away the
     * events [delete], changes [update] in place (their reminders written
     * again) and writes [insert]. Returns how many of [insert] were
     * written.
     *
     * All go in one batch with no yield points, which the calendar
     * provider applies in one transaction: a failure part way leaves the
     * calendar as it was. The provider refuses a batch of 500 operations
     * or more without a yield point, so the batch is kept under
     * [MAX_OPERATIONS]: what does not fit (the furthest new events, as the
     * app sends them soonest first) waits for a later sync. Then the
     * calendar is asked to sync at once, so an event taken away leaves
     * the person's other devices soon too.
     */
    fun apply(
        resolver: ContentResolver,
        calendar: Long,
        insert: List<Map<String, Any?>>,
        update: List<Map<String, Any?>>,
        delete: List<Long>,
    ): Int {
        val ops = ArrayList<ContentProviderOperation>()
        for (id in delete) {
            if (ops.size + 1 > MAX_OPERATIONS) break
            ops.add(
                ContentProviderOperation
                    .newDelete(ContentUris.withAppendedId(Events.CONTENT_URI, id))
                    .build(),
            )
        }
        for (event in update) {
            val id = (event["id"] as? Number)?.toLong() ?: continue
            val start = (event["start"] as? Number)?.toLong() ?: continue
            val minutes = minutesOf(event)
            if (ops.size + 2 + minutes.size > MAX_OPERATIONS) break
            ops.add(
                ContentProviderOperation
                    .newUpdate(ContentUris.withAppendedId(Events.CONTENT_URI, id))
                    .withValues(values(calendar, event, start, minutes))
                    .build(),
            )
            ops.add(
                ContentProviderOperation.newDelete(Reminders.CONTENT_URI)
                    .withSelection("${Reminders.EVENT_ID} = ?", arrayOf(id.toString()))
                    .build(),
            )
            for (before in minutes) {
                ops.add(
                    ContentProviderOperation.newInsert(Reminders.CONTENT_URI)
                        .withValues(reminder(before).apply { put(Reminders.EVENT_ID, id) })
                        .build(),
                )
            }
        }
        var written = 0
        for (event in insert) {
            val start = (event["start"] as? Number)?.toLong() ?: continue
            val minutes = minutesOf(event)
            // One insert for the event and one per reminder; stop before the
            // batch grows too large for one transaction.
            if (ops.size + 1 + minutes.size > MAX_OPERATIONS) break
            val eventAt = ops.size
            ops.add(
                ContentProviderOperation.newInsert(Events.CONTENT_URI)
                    .withValues(values(calendar, event, start, minutes))
                    .build(),
            )
            for (before in minutes) {
                ops.add(
                    ContentProviderOperation.newInsert(Reminders.CONTENT_URI)
                        .withValues(reminder(before))
                        // The id of the event inserted just before.
                        .withValueBackReference(Reminders.EVENT_ID, eventAt)
                        .build(),
                )
            }
            written++
        }
        if (ops.isEmpty()) return 0
        resolver.applyBatch(CalendarContract.AUTHORITY, ops)
        requestSync(resolver, calendar)
        return written
    }

    /**
     * Asks the account [calendar] syncs with to sync now, rather than at
     * its next turn; a calendar kept only on the phone has none to ask.
     */
    private fun requestSync(resolver: ContentResolver, calendar: Long) {
        try {
            resolver.query(
                ContentUris.withAppendedId(Calendars.CONTENT_URI, calendar),
                arrayOf(Calendars.ACCOUNT_NAME, Calendars.ACCOUNT_TYPE),
                null,
                null,
                null,
            )?.use { row ->
                if (!row.moveToFirst()) return
                val name = row.getString(0) ?: return
                val type = row.getString(1) ?: return
                if (type == CalendarContract.ACCOUNT_TYPE_LOCAL) return
                ContentResolver.requestSync(
                    Account(name, type),
                    CalendarContract.AUTHORITY,
                    Bundle().apply {
                        putBoolean(ContentResolver.SYNC_EXTRAS_EXPEDITED, true)
                        putBoolean(ContentResolver.SYNC_EXTRAS_MANUAL, true)
                    },
                )
            }
        } catch (e: Exception) {
            // The events are written; they reach the cloud at the next sync.
        }
    }
}
