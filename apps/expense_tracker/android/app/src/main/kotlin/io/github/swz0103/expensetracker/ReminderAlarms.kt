package io.github.swz0103.expensetracker

/**
 * The alarms behind the kept alerts and their request codes (D45). An
 * alert asked for on the minute gets two alarms at the same time: the
 * exact one, and an inexact twin (setAndAllowWhileIdle) that Android
 * keeps when it cancels the app's exact alarms because their permission
 * was taken away. Whichever goes off first posts the alert; the other
 * finds it posted ([ReminderGrace.Step.DONE]) and does nothing.
 *
 * Request codes: alert `i`'s alarm is `i`, the test notification's
 * [TEST_CODE], taps `1000 + i`, 「確認入帳」 `2000 + i`, the twins
 * `[TWIN_BASE] + i`; [MOST_ALERTS] keeps them apart.
 */
object ReminderAlarms {
    /** The most alarms Android lets one app hold at once (Android 12 and
     *  later refuse more). */
    const val ANDROID_LIMIT = 500

    /** The test notification's alarm, apart from the kept alerts'. */
    const val TEST_CODE = 990

    /** The first request code of the inexact twins. */
    const val TWIN_BASE = 3000

    /**
     * The most alerts armed at once: each may take two alarms, and the
     * test notification one more, all within [ANDROID_LIMIT]. The app
     * sends how many it asks for with each plan (ReminderTiming.most in
     * reminder_rules.dart); this only guards Android's limit.
     */
    const val MOST_ALERTS = (ANDROID_LIMIT - 1) / 2

    /**
     * How many of a plan's alerts are armed when the app asks for at most
     * [asked]: [asked], but never past [MOST_ALERTS] nor below none.
     */
    fun armable(asked: Int): Int = asked.coerceIn(0, MOST_ALERTS)

    /** How many of [given] alerts are left out when [asked] are armed. */
    fun leftOut(given: Int, asked: Int): Int = (given - armable(asked)).coerceAtLeast(0)

    /** The request code of alert [index]'s inexact twin. */
    fun twinCode(index: Int): Int = TWIN_BASE + index

    /** How many alarms [alerts] alerts take, [exact] or not. */
    fun alarms(alerts: Int, exact: Boolean): Int = if (exact) alerts * 2 else alerts
}
