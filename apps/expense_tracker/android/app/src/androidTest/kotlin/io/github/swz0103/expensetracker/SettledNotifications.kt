package io.github.swz0103.expensetracker

import android.app.NotificationManager
import android.service.notification.StatusBarNotification

/**
 * The notifications shown once [done] holds of them, or after [within] ms,
 * whichever first. The notification service applies posts and cancels on
 * its own thread, so what [NotificationManager.getActiveNotifications]
 * reads right after one may be from before it: the device tests wait for
 * it to settle rather than read it at once. With [steady] above 0, [done]
 * must hold for that many ms on end, for what should not show: a post
 * arriving late is caught rather than passed over.
 */
fun NotificationManager.settled(
    within: Long = 3_000,
    steady: Long = 0,
    done: (List<StatusBarNotification>) -> Boolean,
): List<StatusBarNotification> {
    val until = System.currentTimeMillis() + within
    var since: Long? = null
    while (true) {
        val shown = activeNotifications.toList()
        val now = System.currentTimeMillis()
        if (done(shown)) {
            val held = since ?: now.also { since = it }
            if (now - held >= steady) return shown
        } else {
            since = null
        }
        if (now > until) return shown
        Thread.sleep(50)
    }
}

/** The tags of the notifications shown once [done] holds of them, as [settled]. */
fun NotificationManager.settledTags(
    steady: Long = 0,
    done: (Set<String?>) -> Boolean,
): Set<String?> = settled(steady = steady) { shown -> done(shown.map { it.tag }.toSet()) }
    .map { it.tag }
    .toSet()
