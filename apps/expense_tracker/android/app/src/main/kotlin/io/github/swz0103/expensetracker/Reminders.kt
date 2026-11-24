package io.github.swz0103.expensetracker

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

/**
 * The app's notifications (lib/src/features/reminders/model/reminder_alerts.dart).
 * This side decides nothing: the app hands over a plan, each alert with
 * its time on the wall clock, its grace window, its channel and its
 * words, and this keeps it and posts each alert when due.
 *
 * Each alert is due at a time on the wall clock (a date, hour and minute),
 * not at a fixed instant: after the time zone or the clock changes, the
 * alarms are worked out again from the clock, so 9:00 stays 9:00 where the
 * phone now is. The alarms are inexact (setAndAllowWhileIdle), so Android
 * may post one up to an hour late while the phone sleeps (Doze), unless
 * the person asked for reminders on the minute and allowed the app's
 * alarms (setExactAndAllowWhileIdle). An alarm on the minute has an
 * inexact twin at the same time, so the alert still comes when Android
 * cancels the exact alarms with their permission ([ReminderAlarms]).
 *
 * The plan is handed over off the main thread (RemindersHandler.kt) while
 * alarms go off on it: handing over, arming again and an alarm going off
 * each run whole, one at a time.
 *
 * The plan is armed again from what is kept after a restart, an update of
 * the app, a change of time zone or clock, and when alarms on the minute
 * are allowed ([RestartReceiver]). An alert whose time went by meanwhile
 * is posted at once when that was within its grace window, and dropped
 * when longer ago ([ReminderGrace]); one posted is remembered by its id,
 * so it is posted once however often the plan is armed or handed over.
 *
 * Each alert carries a tag (`nudge`, `due:<key>`). A notification already
 * showing whose tag the app no longer lists as wanted is taken away: the
 * daily nudge once something was recorded, a due date once it was booked
 * or paid.
 *
 * What is kept is what the notification shows (its title and text, which
 * can name an amount) and which screen tapping it opens, sealed with a
 * key of the phone's Keystore ([ReminderStore]); an alarm carries only
 * the alert's number, and the words are read when it goes off. The
 * preferences stay on the phone: the cloud backup and a device transfer
 * take only the encrypted ledger copy in files/cloud/
 * (res/xml/data_extraction_rules.xml).
 */
object Reminders {
    private const val TAG = "Reminders"
    private const val PREFS = "reminders"
    private const val EXACT = "exact"
    private const val POSTED = "posted"
    private const val CHANNELS = "channels"

    /** The one channel of versions before each kind had its own; alerts
     *  kept by them post there until the app hands over its plan. */
    private const val LEGACY_CHANNEL = "reminders"
    const val EXTRA_TAG = "tag"
    const val EXTRA_RECURRING = "recurring"
    const val EXTRA_DAY = "day"
    const val EXTRA_CHANNEL = "channel"

    /** The test notification's alarm, apart from the kept alerts'. */
    private const val TEST_ID = ReminderAlarms.TEST_CODE
    private const val TEST_DELAY = 60_000L
    const val EXTRA_TITLE = "title"
    const val EXTRA_TEXT = "text"
    const val EXTRA_ID = "id"

    /** An alert's wall-clock time: year, month (1-12), day, hour, minute. */
    private val CLOCK_FIELDS = listOf("y", "m", "d", "hour", "minute")

    /** The words of an alert, as kept. */
    private val TEXT_FIELDS = listOf("id", "channel", "title", "text", "quick", "tag", "recurring", "day")

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * Keeps [alerts] in place of every alert before, on the minute when
     * [exact]; makes the [channels] they post in (and takes away those
     * [retired]); arms the alerts, posting at once those just past within
     * their grace; and takes away those showing whose tag is not [wanted].
     * The app asks for at most [most] alerts; past them, or past Android's
     * limit ([ReminderAlarms.armable]), the rest are left out, logged, and
     * their number returned for the app to record.
     */
    @Synchronized
    fun replace(
        context: Context,
        alerts: List<Map<String, Any?>>,
        exact: Boolean = false,
        wanted: Set<String>? = null,
        channels: List<Map<String, Any?>> = emptyList(),
        retired: List<String> = emptyList(),
        most: Int = ReminderAlarms.MOST_ALERTS,
    ): Int {
        ensureChannels(context, channels, retired)
        val kept = JSONArray()
        val armed = ReminderAlarms.armable(most)
        val left = ReminderAlarms.leftOut(alerts.size, most)
        if (left > 0) {
            Log.w(TAG, "$left of ${alerts.size} alerts left out: at most $armed are armed")
        }
        for (alert in alerts.take(armed)) {
            val at = (alert["at"] as? Number)?.toLong() ?: continue
            val entry = JSONObject().put("at", at)
            for (name in TEXT_FIELDS) entry.put(name, alert[name] as? String ?: "")
            entry.put("grace", (alert["grace"] as? Number)?.toLong() ?: 0L)
            // The wall-clock time, when the app sends it (it always does
            // now); without it the alert keeps its instant [at].
            val clock = CLOCK_FIELDS.mapNotNull { name ->
                (alert[name] as? Number)?.toInt()?.let { name to it }
            }
            if (clock.size == CLOCK_FIELDS.size) {
                for ((name, value) in clock) entry.put(name, value)
            }
            kept.put(entry)
        }
        val before = ReminderStore.read(context)
        for (i in 0 until before.length()) cancel(context, i)
        ReminderStore.write(context, kept)
        val ids = (0 until kept.length()).map { idOf(kept.getJSONObject(it), it) }
        val posted = ReminderGrace.keptPosted(posted(context), ids)
        prefs(context).edit()
            .putBoolean(EXACT, exact)
            .putStringSet(POSTED, posted)
            .apply()
        scheduleKept(context)
        if (wanted != null) clearShown(context, wanted)
        return left
    }

    /** The ids of the kept alerts already posted. */
    private fun posted(context: Context): Set<String> =
        prefs(context).getStringSet(POSTED, null)?.toSet() ?: emptySet()

    private fun markPosted(context: Context, id: String) {
        prefs(context).edit().putStringSet(POSTED, posted(context) + id).apply()
    }

    /** An alert's id; one kept by an earlier version has none, and goes by
     *  its place. */
    private fun idOf(alert: JSONObject, index: Int): String =
        alert.optString("id").ifEmpty { "legacy:$index" }

    /**
     * Makes each of [channels] (`id`, `name`, `about`), or renames it, and
     * takes away those [retired]; kept, so an alarm going off can make
     * one the phone lost.
     */
    fun ensureChannels(
        context: Context,
        channels: List<Map<String, Any?>>,
        retired: List<String> = emptyList(),
    ) {
        if (channels.isEmpty()) return
        val table = JSONArray()
        for (channel in channels) {
            val id = channel["id"] as? String ?: continue
            table.put(
                JSONObject()
                    .put("id", id)
                    .put("name", channel["name"] as? String ?: id)
                    .put("about", channel["about"] as? String ?: ""),
            )
        }
        prefs(context).edit().putString(CHANNELS, table.toString()).apply()
        if (Build.VERSION.SDK_INT < 26) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        for (i in 0 until table.length()) createChannel(manager, table.getJSONObject(i))
        for (id in retired) manager.deleteNotificationChannel(id)
    }

    private fun createChannel(manager: NotificationManager, channel: JSONObject) {
        if (Build.VERSION.SDK_INT < 26) return
        // Making one that exists only renames it; what the person set stays.
        manager.createNotificationChannel(
            NotificationChannel(
                channel.getString("id"),
                channel.getString("name"),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { description = channel.optString("about") },
        )
    }

    /**
     * The channel to post in for [wanted]: itself, made again from the
     * kept names when the phone lost it; the channel of earlier versions
     * for an alert kept by them; null when there is none to post in.
     */
    private fun channelFor(context: Context, wanted: String): String? {
        if (Build.VERSION.SDK_INT < 26) return wanted.ifEmpty { LEGACY_CHANNEL }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val id = wanted.ifEmpty { LEGACY_CHANNEL }
        if (manager.getNotificationChannel(id) != null) return id
        val table = try {
            JSONArray(prefs(context).getString(CHANNELS, null) ?: "[]")
        } catch (e: Exception) {
            JSONArray()
        }
        for (i in 0 until table.length()) {
            val channel = table.getJSONObject(i)
            if (channel.optString("id") == id) {
                createChannel(manager, channel)
                return id
            }
        }
        return null
    }

    /** Takes away the app's notifications showing whose tag is not [wanted]. */
    private fun clearShown(context: Context, wanted: Set<String>) {
        if (Build.VERSION.SDK_INT < 23) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        for (shown in manager.activeNotifications) {
            val tag = shown.tag ?: continue
            // The test notification stays until swiped away.
            if (tag != "test" && tag !in wanted) manager.cancel(tag, shown.id)
        }
    }

    /** Whether alarms may go off on the minute. */
    fun exactAllowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarms.canScheduleExactAlarms()
    }

    /** Sets [intent]'s alarm for [at], on the minute when asked and allowed. */
    private fun setAlarm(context: Context, at: Long, intent: PendingIntent, exact: Boolean) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (exact && exactAllowed(context)) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        }
    }

    /**
     * Arms the kept alert numbered [index] for [at]: its alarm, and when
     * that one is on the minute, its inexact twin at the same time; without
     * an alarm on the minute, no twin is left.
     */
    private fun arm(context: Context, index: Int, at: Long, exact: Boolean) {
        // The same request codes replace the alarms set before.
        setAlarm(context, at, pending(context, index), exact)
        if (exact && exactAllowed(context)) {
            setAlarm(context, at, twin(context, index), exact = false)
        } else {
            cancelIntent(context, twin(context, index))
        }
    }

    /** A test notification in a minute, as the reminders would come, with
     *  the app's words in its [channel]. */
    fun test(context: Context, exact: Boolean, channel: String, title: String, text: String) {
        val intent = Intent(context, ReminderReceiver::class.java)
            .putExtra(EXTRA_ID, TEST_ID)
            .putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_TEXT, text)
            .putExtra(EXTRA_CHANNEL, channel)
            .putExtra(EXTRA_TAG, "test")
            .putExtra(MainActivity.EXTRA_QUICK, "")
        val pending = PendingIntent.getBroadcast(
            context,
            TEST_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        setAlarm(context, System.currentTimeMillis() + TEST_DELAY, pending, exact)
    }

    /**
     * When [alert] is due, in milliseconds: its wall-clock time in the
     * phone's time zone now, or the instant it was given when it carries
     * no wall-clock time (alerts kept by an older version).
     */
    private fun dueAt(alert: JSONObject): Long {
        if (!alert.has("y")) return alert.getLong("at")
        return wallClock(
            alert.getInt("y"),
            alert.getInt("m"),
            alert.getInt("d"),
            alert.getInt("hour"),
            alert.getInt("minute"),
        )
    }

    /**
     * The instant a wall-clock time falls on in [zone] (the phone's own by
     * default); [month] counts from 1, as the app writes it.
     */
    fun wallClock(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        zone: TimeZone = TimeZone.getDefault(),
    ): Long = Calendar.getInstance(zone).apply {
        clear()
        set(year, month - 1, day, hour, minute)
    }.timeInMillis

    /**
     * Arms the kept plan at the clock now: an alarm for each alert still to
     * come; each just past within its grace posted at once (once); each
     * past longer ago dropped.
     */
    @Synchronized
    fun scheduleKept(context: Context) {
        val kept = ReminderStore.read(context)
        val now = System.currentTimeMillis()
        val exact = prefs(context).getBoolean(EXACT, false)
        val posted = posted(context)
        for (i in 0 until kept.length()) {
            val alert = kept.getJSONObject(i)
            val at = dueAt(alert)
            val id = idOf(alert, i)
            when (ReminderGrace.step(at, alert.optLong("grace"), now, id in posted)) {
                ReminderGrace.Step.ARM -> arm(context, i, at, exact)
                ReminderGrace.Step.POST_NOW -> {
                    cancel(context, i)
                    postKept(context, i, alert)
                }
                ReminderGrace.Step.DROP, ReminderGrace.Step.DONE -> cancel(context, i)
            }
        }
    }

    /**
     * Posts the kept alert numbered [index], and remembers it was only
     * once it is showing: one that could not be posted (notifications off,
     * no channel) is posted when the plan is armed again within its grace.
     */
    fun postKept(context: Context, index: Int, alert: JSONObject) {
        ReminderGrace.postOnce(
            show = {
                show(
                    context,
                    index,
                    alert.optString("title"),
                    alert.optString("text"),
                    alert.optString("quick"),
                    alert.optString("tag"),
                    alert.optString("recurring"),
                    alert.optString("day"),
                    alert.optString("channel"),
                )
            },
            markPosted = { markPosted(context, idOf(alert, index)) },
        )
    }

    /** The alarm of the kept alert numbered [index] going off at [now]:
     *  posted when its time has come within its grace, set again when
     *  the clock moved so it is not due yet, dropped otherwise. */
    @Synchronized
    fun alarmWentOff(context: Context, index: Int, now: Long = System.currentTimeMillis()) {
        val alert = ReminderStore.read(context).optJSONObject(index) ?: return
        val at = dueAt(alert)
        val id = idOf(alert, index)
        when (ReminderGrace.step(at, alert.optLong("grace"), now, id in posted(context))) {
            ReminderGrace.Step.ARM ->
                arm(context, index, at, prefs(context).getBoolean(EXACT, false))
            ReminderGrace.Step.POST_NOW -> {
                // The other alarm of the pair has nothing left to do.
                cancel(context, index)
                postKept(context, index, alert)
            }
            ReminderGrace.Step.DROP, ReminderGrace.Step.DONE -> cancel(context, index)
        }
    }

    /** An alarm for the alert numbered [id]: only the number goes with
     *  it, and its words are read sealed when it goes off. */
    private fun pending(context: Context, id: Int): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java).putExtra(EXTRA_ID, id)
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** The inexact twin of the alarm of the alert numbered [id]: the same
     *  intent under its own request code. */
    private fun twin(context: Context, id: Int): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java).putExtra(EXTRA_ID, id)
        return PendingIntent.getBroadcast(
            context,
            ReminderAlarms.twinCode(id),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Takes away the alarms of the alert numbered [id], twin included. */
    private fun cancel(context: Context, id: Int) {
        cancelIntent(context, pending(context, id))
        cancelIntent(context, twin(context, id))
    }

    private fun cancelIntent(context: Context, pending: PendingIntent) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarms.cancel(pending)
        // And the intent itself, so nothing of a taken-away alert is left
        // with the system.
        pending.cancel()
    }

    /** Whether notifications may be posted. */
    fun allowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    private fun confirming(
        context: Context,
        id: Int,
        tag: String,
        recurring: String,
        day: String,
    ): PendingIntent {
        val intent = Intent(context, ConfirmReceiver::class.java)
            .putExtra(EXTRA_ID, id)
            .putExtra(EXTRA_TAG, tag)
            .putExtra(EXTRA_RECURRING, recurring)
            .putExtra(EXTRA_DAY, day)
        // Request codes from 2000 on, apart from the alarms and taps.
        return PendingIntent.getBroadcast(
            context,
            2000 + id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Posts one alert in [channel]; tapping it opens the app, or the
     *  composer. False when nothing was posted: notifications are off, or
     *  there is no channel to post in. */
    fun show(
        context: Context,
        id: Int,
        title: String,
        text: String,
        quick: String,
        tag: String = "",
        recurring: String = "",
        day: String = "",
        channel: String = "",
    ): Boolean {
        if (!allowed(context)) return false
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val postIn = channelFor(context, channel) ?: return false
        // Request codes from 1000 on, apart from the widget's.
        val tap = MainActivity.opening(context, quick, 1000 + id)
        val notification = NotificationCompat.Builder(context, postIn)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .apply {
                // A recurring item due can be confirmed from here: booked
                // when the ledger is next opened or comes back.
                if (recurring.isNotEmpty() && day.isNotEmpty()) {
                    addAction(0, "確認入帳", confirming(context, id, tag, recurring, day))
                }
            }
            // Amounts stay off the lock screen.
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(
                NotificationCompat.Builder(context, postIn)
                    .setSmallIcon(R.drawable.ic_notification)
                    .setContentTitle("記帳本")
                    .setContentText("有一則提醒")
                    .build(),
            )
            .build()
        // Tagged, so one no longer wanted can be taken away.
        manager.notify(tag.ifEmpty { null }, id, notification)
        return true
    }
}

/** Posts an alert when its alarm goes off. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(Reminders.EXTRA_ID, 0)
        // The test notification carries its own words; a kept alert's are
        // read sealed.
        intent.getStringExtra(Reminders.EXTRA_TITLE)?.let { title ->
            Reminders.show(
                context,
                id,
                title,
                intent.getStringExtra(Reminders.EXTRA_TEXT) ?: "",
                intent.getStringExtra(MainActivity.EXTRA_QUICK) ?: "",
                intent.getStringExtra(Reminders.EXTRA_TAG) ?: "",
                "",
                "",
                intent.getStringExtra(Reminders.EXTRA_CHANNEL) ?: "",
            )
            return
        }
        Reminders.alarmWentOff(context, id)
    }
}

/**
 * 「確認入帳」 on a due notification: the item and its day go into the
 * ledger's inbox, sealed, to be booked when the ledger is next opened or
 * comes back to the front; the notification goes. Nothing is booked here:
 * the ledger stays locked.
 */
class ConfirmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val recurring = intent.getStringExtra(Reminders.EXTRA_RECURRING) ?: return
        val day = intent.getStringExtra(Reminders.EXTRA_DAY) ?: return
        // Ids and days only: no character JSON would need to escape.
        if (!Regex("^[A-Za-z0-9_-]{1,64}$").matches(recurring) ||
            !Regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$").matches(day)
        ) {
            return
        }
        val plain = "{\"kind\":\"confirm\",\"recurring\":\"$recurring\",\"day\":\"$day\"}"
        val posted = try {
            InboxWriter.post(context, plain.toByteArray(Charsets.UTF_8))
        } catch (e: Exception) {
            false
        }
        if (!posted) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val tag = intent.getStringExtra(Reminders.EXTRA_TAG) ?: ""
        manager.cancel(tag.ifEmpty { null }, intent.getIntExtra(Reminders.EXTRA_ID, 0))
    }
}

/**
 * Arms the kept plan again after the phone restarts or the app updates,
 * when the clock or time zone changes (each alert's time is worked out
 * again from its wall-clock time, in the time zone the phone is in now),
 * and when alarms on the minute are allowed (they ring on the minute from
 * then on). Taking that permission away stops the app and cancels its
 * alarms on the minute, and Android tells nothing of it: their inexact
 * twins still ring ([ReminderAlarms]), and the plan is armed again,
 * inexact, when the app is next opened or the phone restarts.
 */
class RestartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in ACTIONS) Reminders.scheduleKept(context)
    }

    companion object {
        /** The broadcasts that arm the plan again; the manifest lists the same. */
        val ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            // Android 12 and later.
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED,
        )
    }
}
