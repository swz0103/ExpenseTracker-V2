package io.github.swz0103.expensetracker

import android.content.Context
import androidx.fragment.app.FragmentActivity

/**
 * What MainActivity needs of the self-update, in the sideload build: the
 * installer's channel handler and the daily look for a newer version. The
 * play build has a [SelfUpdate] of the same name that does none of it
 * (src/play).
 */
internal object SelfUpdate {
    fun handlers(activity: FragmentActivity): List<ChannelHandler> =
        listOf(UpdateHandler(activity))

    /** Looks for a newer version once a day while 自動檢查新版本 is on. */
    fun start(context: Context) = UpdateWorker.schedule(context)
}
