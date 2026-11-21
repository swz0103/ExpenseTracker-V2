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
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Notifications on the phone itself (Reminders.kt): posted on the app's
 * channel with its tag, and taken away once no longer wanted.
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

    @After
    fun clear() = manager.cancelAll()

    @Test
    fun aDueItemIsShownOnTheRemindersChannelWithItsTag() {
        assertTrue(Reminders.allowed(context))
        Reminders.show(context, 4242, "扣款：Netflix 390", "定期交易", "", tag = "due:test-netflix")
        val shown = manager.activeNotifications.single { it.id == 4242 }
        assertEquals("due:test-netflix", shown.tag)
        if (Build.VERSION.SDK_INT >= 26) {
            assertEquals("reminders", shown.notification.channelId)
        }
    }

    @Test
    fun aNoticeNoLongerWantedIsTakenAway() {
        Reminders.show(context, 4243, "繳卡費", "", "", tag = "due:test-card")
        Reminders.show(context, 4244, "扣款", "", "", tag = "due:test-kept")
        Reminders.replace(context, emptyList(), wanted = setOf("due:test-kept"))
        val tags = manager.activeNotifications.map { it.tag }.toSet()
        assertTrue("due:test-kept" in tags)
        assertTrue("due:test-card" !in tags)
    }

    @Test
    fun theWordsKeptForLaterAreSealed() {
        val prefs = context.getSharedPreferences("reminders", Context.MODE_PRIVATE)
        // As 0.19 kept them: in plain words, read once and sealed.
        prefs.edit().putString("alerts", """[{"at":1,"title":"扣款：Netflix 390"}]""").commit()
        assertEquals("扣款：Netflix 390", ReminderStore.read(context).getJSONObject(0).getString("title"))
        val later = System.currentTimeMillis() + 86_400_000L
        Reminders.replace(context, listOf(mapOf("at" to later, "title" to "繳卡費 12,800", "text" to "日常信用卡")))
        val written = prefs.all.values.joinToString(" ")
        assertTrue(written, "12,800" !in written && "Netflix" !in written && "日常信用卡" !in written)
        assertTrue(!prefs.contains("alerts"))
        assertEquals("繳卡費 12,800", ReminderStore.read(context).getJSONObject(0).getString("title"))
        Reminders.replace(context, emptyList())
    }
}
