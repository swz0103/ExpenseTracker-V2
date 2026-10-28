package io.github.swz0103.expensetracker

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File
import java.util.Calendar

/**
 * The home-screen widget 本月概況: the month's spending and what is left
 * of the budget, or only the share used, as chosen in 設定 › 外觀, with
 * 記支出 and 記收入 below. It shows the text the app left in widget.json
 * (lib/src/features/overview/model/home_widget.dart) and never reads the
 * ledger, so it shows it while the ledger is locked; with no figures
 * chosen there is no file and it says where to turn them on.
 */
class SummaryWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = views(context)
        for (id in ids) manager.updateAppWidget(id, views)
    }

    companion object {
        /** Shows the snapshot again on every 本月概況 on the home screen. */
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, SummaryWidget::class.java))
            if (ids.isEmpty()) return
            val views = views(context)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private fun views(context: Context): RemoteViews {
            val shown = WidgetView.of(read(context), currentMonth())
            val views = RemoteViews(context.packageName, R.layout.summary_widget)
            views.setTextViewText(R.id.summary_title, shown.title)
            views.setTextViewText(R.id.summary_figure, shown.figure)
            views.setTextViewText(R.id.summary_detail, shown.detail)
            views.setViewVisibility(
                R.id.summary_detail,
                if (shown.detail.isEmpty()) View.GONE else View.VISIBLE,
            )
            val progress = shown.progress
            if (progress == null) {
                views.setViewVisibility(R.id.summary_progress, View.GONE)
            } else {
                views.setViewVisibility(R.id.summary_progress, View.VISIBLE)
                views.setProgressBar(R.id.summary_progress, 100, progress, false)
            }
            views.setOnClickPendingIntent(R.id.summary_body, MainActivity.opening(context, "", 6))
            views.setOnClickPendingIntent(R.id.summary_expense, MainActivity.opening(context, "expense", 4))
            views.setOnClickPendingIntent(R.id.summary_income, MainActivity.opening(context, "income", 5))
            return views
        }

        private fun read(context: Context): WidgetView.Snapshot? = try {
            val file = File(context.filesDir, "widget.json")
            if (!file.exists()) {
                null
            } else {
                val json = JSONObject(file.readText())
                WidgetView.Snapshot(
                    month = json.optString("month"),
                    title = json.optString("title"),
                    figure = json.optString("figure"),
                    detail = json.optString("detail"),
                    progress = if (json.isNull("progress")) null else json.optInt("progress"),
                )
            }
        } catch (e: Exception) {
            null
        }

        private fun currentMonth(): String {
            val now = Calendar.getInstance()
            return "%04d-%02d".format(now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1)
        }
    }
}

/** What 本月概況 shows for a snapshot; kept apart from Android to be tested. */
internal object WidgetView {
    data class Snapshot(
        val month: String,
        val title: String,
        val figure: String,
        val detail: String,
        val progress: Int?,
    )

    data class Shown(val title: String, val figure: String, val detail: String, val progress: Int?)

    /**
     * The snapshot as it stands in [month]: one from an earlier month says
     * to open the app rather than show last month's figures as this one's.
     */
    fun of(snapshot: Snapshot?, month: String): Shown = when {
        snapshot == null -> Shown("記帳本", "本月概況", "到 設定 › 外觀 選擇要顯示的數字", null)
        snapshot.month != month -> Shown("本月概況", "—", "打開 App 更新本月數字", null)
        else -> Shown(
            snapshot.title,
            snapshot.figure,
            snapshot.detail,
            snapshot.progress?.coerceIn(0, 100),
        )
    }
}
