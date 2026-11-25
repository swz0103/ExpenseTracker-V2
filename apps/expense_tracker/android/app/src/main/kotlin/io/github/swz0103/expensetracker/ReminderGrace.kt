package io.github.swz0103.expensetracker

/**
 * What becomes of a kept alert at a given moment: the one rule applied
 * when the plan is handed over, at each re-arm (restart, app update,
 * time zone or clock change, alarms on the minute allowed) and when its
 * alarm goes off. The app decides each alert's time and grace window
 * (reminder_rules.dart); this only compares them with the clock.
 */
object ReminderGrace {
    enum class Step {
        /** Still to come: its alarm is set. */
        ARM,

        /** Its time passed no longer ago than its grace: posted now, once. */
        POST_NOW,

        /** Its time passed longer ago than its grace: dropped. */
        DROP,

        /** Posted already: nothing more. */
        DONE,
    }

    /**
     * The step for an alert due at [at] with a grace of [grace]
     * milliseconds, at [now]; [posted] when it was posted before.
     */
    fun step(at: Long, grace: Long, now: Long, posted: Boolean): Step = when {
        posted -> Step.DONE
        at > now -> Step.ARM
        now - at <= grace -> Step.POST_NOW
        else -> Step.DROP
    }

    /**
     * Posts an alert with [show] and, only when it did post, remembers it
     * with [markPosted]: an alert that could not be posted (notifications
     * off, no channel) stays due within its grace. True when posted.
     */
    fun postOnce(show: () -> Boolean, markPosted: () -> Unit): Boolean {
        val shown = show()
        if (shown) markPosted()
        return shown
    }

    /** Of the ids posted before, those the new plan still holds. */
    fun keptPosted(posted: Set<String>, planned: Collection<String>): Set<String> =
        posted.intersect(planned.toSet())
}
