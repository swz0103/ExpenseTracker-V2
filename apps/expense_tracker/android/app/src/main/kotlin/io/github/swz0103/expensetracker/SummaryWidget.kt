package io.github.swz0103.expensetracker

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File
import java.util.Calendar

/**
 * The home-screen widget 本月概況: the month's spending over its budget
 * bar, this week day by day, and 支出 and 收入 at the foot. Made smaller
 * it keeps only what is left of the budget and the two buttons, one row
 * high or square. It shows what the app left in widget.json
 * (lib/src/features/overview/model/home_widget.dart) and never reads the
 * ledger, so it shows it while the ledger is locked; with no figures
 * chosen in 設定 › 外觀 there is no file and it says where to turn them on.
 */
class SummaryWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = views(context)
        for (id in ids) manager.updateAppWidget(id, views)
    }

    companion object {
        /** Shows the snapshot again on every widget on the home screen. */
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for (provider in listOf(SummaryWidget::class.java, QuickWidget::class.java)) {
                val ids = manager.getAppWidgetIds(ComponentName(context, provider))
                if (ids.isEmpty()) continue
                val views = views(context, small = provider == QuickWidget::class.java)
                for (id in ids) manager.updateAppWidget(id, views)
            }
        }

        /**
         * The widget at every size: from Android 12 the launcher picks the
         * largest that fits; before it, the full widget, or one row high
         * when [small] (記一筆, placed before the two were one).
         */
        fun views(context: Context, small: Boolean = false): RemoteViews {
            val shown = WidgetView.of(read(context), currentMonth())
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                return if (small) compact(context, shown, R.layout.quick_widget) else full(context, shown)
            }
            return RemoteViews(
                mapOf(
                    SizeF(110f, 40f) to compact(context, shown, R.layout.quick_widget),
                    SizeF(110f, 110f) to compact(context, shown, R.layout.widget_square),
                    SizeF(220f, 150f) to full(context, shown),
                ),
            )
        }

        private val bars = intArrayOf(R.id.bar0, R.id.bar1, R.id.bar2, R.id.bar3, R.id.bar4, R.id.bar5, R.id.bar6)
        private val todays = intArrayOf(R.id.today0, R.id.today1, R.id.today2, R.id.today3, R.id.today4, R.id.today5, R.id.today6)
        private val dots = intArrayOf(R.id.dot0, R.id.dot1, R.id.dot2, R.id.dot3, R.id.dot4, R.id.dot5, R.id.dot6)
        private val labels = intArrayOf(R.id.label0, R.id.label1, R.id.label2, R.id.label3, R.id.label4, R.id.label5, R.id.label6)
        private const val ACCENT = 0xFF35657A.toInt()
        private const val DAY = 0xFF9AA4A9.toInt()

        private fun full(context: Context, shown: WidgetView.Shown): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.summary_widget)
            views.setTextViewText(R.id.summary_title, shown.title)
            views.setTextViewText(R.id.summary_figure, shown.figure)
            views.setTextViewText(R.id.summary_budget, shown.budget)
            views.setTextViewText(R.id.summary_detail, shown.detail)
            bar(views, R.id.summary_bar, shown)
            val week = shown.week
            if (week == null) {
                views.setViewVisibility(R.id.week_box, View.GONE)
            } else {
                views.setViewVisibility(R.id.week_box, View.VISIBLE)
                views.setTextViewText(R.id.week_total, shown.weekTotal)
                visible(views, R.id.week_total, shown.weekTotal.isNotEmpty())
                for (i in 0 until 7) {
                    val share = week[i]
                    val today = i == shown.today
                    visible(views, dots[i], share < 0)
                    visible(views, bars[i], share >= 0 && !today)
                    visible(views, todays[i], share >= 0 && today)
                    // A day with nothing spent still shows a sliver.
                    val height = if (share <= 0) 0 else share.coerceIn(6, 100)
                    views.setProgressBar(if (today) todays[i] else bars[i], 100, height, false)
                    views.setTextColor(labels[i], if (today) ACCENT else DAY)
                }
            }
            views.setOnClickPendingIntent(R.id.summary_body, MainActivity.opening(context, "", 6))
            views.setOnClickPendingIntent(R.id.summary_expense, MainActivity.opening(context, "expense", 4))
            views.setOnClickPendingIntent(R.id.summary_income, MainActivity.opening(context, "income", 5))
            return views
        }

        private fun compact(context: Context, shown: WidgetView.Shown, layout: Int): RemoteViews {
            val views = RemoteViews(context.packageName, layout)
            views.setTextViewText(R.id.short_label, shown.shortLabel)
            views.setTextViewText(R.id.short_figure, shown.shortFigure)
            bar(views, R.id.short_bar, shown)
            views.setOnClickPendingIntent(R.id.short_body, MainActivity.opening(context, "", 3))
            views.setOnClickPendingIntent(R.id.short_expense, MainActivity.opening(context, "expense", 1))
            views.setOnClickPendingIntent(R.id.short_income, MainActivity.opening(context, "income", 2))
            return views
        }

        private fun bar(views: RemoteViews, id: Int, shown: WidgetView.Shown) {
            val progress = shown.progress
            if (progress == null) {
                views.setViewVisibility(id, View.GONE)
                return
            }
            views.setViewVisibility(id, View.VISIBLE)
            views.setProgressBar(id, 100, progress, false)
            views.setInt(id, "setSecondaryProgress", shown.pace ?: 0)
        }

        private fun visible(views: RemoteViews, id: Int, shown: Boolean) =
            views.setViewVisibility(id, if (shown) View.VISIBLE else View.GONE)

        private fun read(context: Context): WidgetView.Snapshot? = try {
            val file = File(context.filesDir, "widget.json")
            if (!file.exists()) null else WidgetView.parse(JSONObject(file.readText()))
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
        val budget: String = "",
        val pace: Int? = null,
        val week: List<Int>? = null,
        val weekTotal: String = "",
        val today: Int = -1,
        val shortLabel: String = title,
        val shortFigure: String = figure,
    )

    data class Shown(
        val title: String,
        val figure: String,
        val detail: String,
        val progress: Int?,
        val budget: String = "",
        val pace: Int? = null,
        val week: List<Int>? = null,
        val weekTotal: String = "",
        val today: Int = -1,
        val shortLabel: String = title,
        val shortFigure: String = figure,
    )

    /** A snapshot as the app wrote it; one from before the week was added still reads. */
    fun parse(json: JSONObject): Snapshot {
        val title = json.optString("title")
        val figure = json.optString("figure")
        val days = json.optJSONArray("week")
        val week = if (days == null || days.length() != 7) null else List(7) { days.optInt(it, -1) }
        return Snapshot(
            month = json.optString("month"),
            title = title,
            figure = figure,
            detail = json.optString("detail"),
            progress = if (json.isNull("progress")) null else json.optInt("progress"),
            budget = json.optString("budget"),
            pace = if (json.isNull("pace")) null else json.optInt("pace"),
            week = week,
            weekTotal = json.optString("weekTotal"),
            today = json.optInt("today", -1),
            shortLabel = json.optString("shortLabel", title),
            shortFigure = json.optString("shortFigure", figure),
        )
    }

    /**
     * The snapshot as it stands in [month]: one from an earlier month says
     * to open the app rather than show last month's figures as this one's.
     */
    fun of(snapshot: Snapshot?, month: String): Shown = when {
        snapshot == null -> Shown("記帳本", "本月概況", "到 設定 › 外觀 選擇要顯示的數字", null)
        snapshot.month != month -> Shown("本月概況", "—", "打開 App 更新本月數字", null)
        else -> Shown(
            title = snapshot.title,
            figure = snapshot.figure,
            detail = snapshot.detail,
            progress = snapshot.progress?.coerceIn(0, 100),
            budget = snapshot.budget,
            pace = snapshot.pace?.coerceIn(0, 100),
            week = snapshot.week,
            weekTotal = snapshot.weekTotal,
            today = snapshot.today,
            shortLabel = snapshot.shortLabel,
            shortFigure = snapshot.shortFigure,
        )
    }
}
