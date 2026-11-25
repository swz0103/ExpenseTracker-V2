package io.github.swz0103.expensetracker

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Notifications on the phone itself (Reminders.kt): posted on the channel
 * of their kind with their tag, and taken away once no longer wanted. The
 * channels are the app's to hand over (reminder_rules.dart); the test
 * hands over the one it posts in, as the app does before any alert.
 */
@RunWith(AndroidJUnit4::class)
class RemindersDeviceTest {
    @get:Rule
    val permission: GrantPermissionRule =
        if (Build.VERSION.SDK_INT >= 33) {
            GrantPermissionRule.grant(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            GrantPermissionRule.grant()
        }

    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    @Before
    fun channels() = Reminders.ensureChannels(context, listOf(mapOf("id" to CHANNEL, "name" to "到期提醒")))

    @After
    fun clear() = manager.cancelAll()

    @Test
    fun aDueItemIsShownOnTheRemindersChannelWithItsTag() {
        assertTrue(Reminders.allowed(context))
        Reminders.show(context, 4242, "扣款：Netflix 390", "定期交易", "", tag = "due:test-netflix", channel = CHANNEL)
        val shown = manager.activeNotifications.single { it.id == 4242 }
        assertEquals("due:test-netflix", shown.tag)
        if (Build.VERSION.SDK_INT >= 26) {
            assertEquals(CHANNEL, shown.notification.channelId)
        }
    }

    @Test
    fun aNoticeNoLongerWantedIsTakenAway() {
        Reminders.show(context, 4243, "繳卡費", "", "", tag = "due:test-card", channel = CHANNEL)
        Reminders.show(context, 4244, "扣款", "", "", tag = "due:test-kept", channel = CHANNEL)
        Reminders.replace(context, emptyList(), wanted = setOf("due:test-kept"))
        // The notification service applies posts and cancels on its own
        // thread: wait for it to settle rather than read it at once.
        val tags = settled { "due:test-kept" in it && "due:test-card" !in it }
        assertTrue("due:test-kept" in tags)
        assertTrue("due:test-card" !in tags)
    }

    /** The tags shown once [done] holds, or after 3 s, whichever first. */
    private fun settled(done: (Set<String?>) -> Boolean): Set<String?> {
        val until = System.currentTimeMillis() + 3_000
        while (true) {
            val tags = manager.activeNotifications.map { it.tag }.toSet()
            if (done(tags) || System.currentTimeMillis() > until) return tags
            Thread.sleep(50)
        }
    }

    @Test
    fun aDueItemIsConfirmedAndShownLockedInTheAppsWords() {
        // NAT-1: the app hands its words over with the plan; they are kept
        // for the alarms going off while it is closed.
        Reminders.keepWords(
            context,
            mapOf("confirm" to "入帳了", "publicTitle" to "提醒", "publicText" to "打開看看"),
        )
        Reminders.show(
            context, 4245, "扣款：Netflix 390", "定期交易", "",
            tag = "due:test-words", recurring = "netflix", day = "2026-11-25", channel = CHANNEL,
        )
        val shown = manager.activeNotifications.single { it.id == 4245 }.notification
        assertEquals("入帳了", shown.actions.single().title.toString())
        assertEquals("提醒", shown.publicVersion.extras.getCharSequence("android.title").toString())
        assertEquals("打開看看", shown.publicVersion.extras.getCharSequence("android.text").toString())
        Reminders.keepWords(context, NativeWords.run {
            mapOf("confirm" to REMINDER_CONFIRM, "publicTitle" to REMINDER_PUBLIC_TITLE, "publicText" to REMINDER_PUBLIC_TEXT)
        })
    }

    @Test
    fun theWordsKeptForLaterAreSealed() {
        val prefs = context.getSharedPreferences("reminders", Context.MODE_PRIVATE)
        // As 0.19 kept them: in plain words only, read once and sealed.
        prefs.edit().clear().putString("alerts", """[{"at":1,"title":"扣款：Netflix 390"}]""").commit()
        assertEquals("扣款：Netflix 390", ReminderStore.read(context).getJSONObject(0).getString("title"))
        val later = System.currentTimeMillis() + 86_400_000L
        Reminders.replace(context, listOf(mapOf("at" to later, "title" to "繳卡費 12,800", "text" to "日常信用卡")))
        val written = prefs.all.values.joinToString(" ")
        assertTrue(written, "12,800" !in written && "Netflix" !in written && "日常信用卡" !in written)
        assertTrue(!prefs.contains("alerts"))
        assertEquals("繳卡費 12,800", ReminderStore.read(context).getJSONObject(0).getString("title"))
        Reminders.replace(context, emptyList())
    }

    @Test
    fun anAlertThatCouldNotBePostedIsPostedWhenHandedOverAgain() {
        // Review 21 finding 1. Before Android 8 every alert has a channel.
        if (Build.VERSION.SDK_INT < 26) return
        fun alert(channel: String) = mapOf(
            "at" to System.currentTimeMillis() - 60_000L,
            "grace" to 3_600_000L,
            "id" to "due:test-missed@1",
            "title" to "繳卡費",
            "tag" to "due:test-missed",
            "channel" to channel,
        )
        // A channel the phone does not have and the app never named:
        // nothing to post in.
        Reminders.replace(context, listOf(alert("test-no-such-channel")))
        assertTrue(manager.activeNotifications.none { it.tag == "due:test-missed" })
        // Handed over again with its channel, within its grace: posted now.
        Reminders.replace(context, listOf(alert(CHANNEL)))
        assertTrue(manager.activeNotifications.any { it.tag == "due:test-missed" })
        Reminders.replace(context, emptyList())
    }

    private companion object {
        /** The channel of due reminders, as the app names it. */
        const val CHANNEL = "due"
    }
}
