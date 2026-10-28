package io.github.swz0103.expensetracker

import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Shows the home-screen widgets' snapshot again (lib/src/app/android/widgets.dart). */
class WidgetsPart(private val activity: FragmentActivity) : ChannelPart {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != "refreshWidgets") return false
        try {
            SummaryWidget.updateAll(activity.applicationContext)
            result.success(null)
        } catch (e: Exception) {
            result.error("widgets", e.message, null)
        }
        return true
    }
}
