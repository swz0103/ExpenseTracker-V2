package io.github.swz0103.expensetracker

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The alarms behind reminders (Reminders.kt) on the phone itself: one is
 * set for each alert to come and taken away with it, and when it goes off
 * the notification says the words kept sealed.
 */
@RunWith(AndroidJUnit4::class)
class ReminderAlarmsDeviceTest {
    @get:Rule
    val permission: GrantPermissionRule =
        if (Build.VERSION.SDK_INT >= 33) {
            GrantPermissionRule.grant(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            GrantPermissionRule.grant()
        }

    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    /** The alarm of alert [id], if one is set; none is made by asking. */
    private fun alarm(id: Int): PendingIntent? = PendingIntent.getBroadcast(
        context,
        id,
        Intent(context, ReminderReceiver::class.java),
        PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
    )

    @After
    fun clear() {
        Reminders.replace(context, emptyList())
        manager.cancelAll()
    }

    @Test
    fun anAlarmIsSetForEachAlertAndTakenAwayWithIt() {
        val tomorrow = System.currentTimeMillis() + 86_400_000L
        Reminders.replace(
            context,
            listOf(
                mapOf("at" to tomorrow, "title" to "繳卡費", "tag" to "due:card"),
                mapOf("at" to tomorrow + 60_000L, "title" to "扣款", "tag" to "due:rent"),
            ),
        )
        assertNotNull(alarm(0))
        assertNotNull(alarm(1))
        Reminders.replace(context, emptyList())
        assertNull(alarm(0))
        assertNull(alarm(1))
    }

    @Test
    fun anAlarmGoingOffShowsTheSealedWords() {
        Reminders.replace(
            context,
            listOf(
                mapOf(
                    "at" to System.currentTimeMillis() + 86_400_000L,
                    "title" to "繳卡費 12,800",
                    "text" to "日常信用卡",
                    "tag" to "due:card",
                ),
            ),
        )
        // As the alarm would: only the alert's number comes with it.
        ReminderReceiver().onReceive(
            context,
            Intent(context, ReminderReceiver::class.java).putExtra(Reminders.EXTRA_ID, 0),
        )
        val shown = manager.activeNotifications.single { it.tag == "due:card" }
        assertEquals("繳卡費 12,800", shown.notification.extras.getString("android.title"))
        assertEquals("日常信用卡", shown.notification.extras.getString("android.text"))
    }
}
