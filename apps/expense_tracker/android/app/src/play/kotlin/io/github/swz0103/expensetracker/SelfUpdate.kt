package io.github.swz0103.expensetracker

import android.content.Context
import androidx.fragment.app.FragmentActivity
import androidx.work.WorkManager

/**
 * The play build does not update itself: Google Play does not allow an app
 * to update itself by other means than its own, so there is no installer
 * handler, no update check and no network call for one (the sideload build
 * has them, src/sideload). Same name and shape as the sideload build's
 * [SelfUpdate], which MainActivity calls.
 */
internal object SelfUpdate {
    fun handlers(@Suppress("UNUSED_PARAMETER") activity: FragmentActivity): List<ChannelHandler> =
        emptyList()

    /** Nothing is looked for; a daily look left by a sideload build is dropped. */
    fun start(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork("updates")
    }
}
