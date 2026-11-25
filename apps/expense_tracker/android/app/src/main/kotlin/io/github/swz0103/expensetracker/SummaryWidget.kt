package io.github.swz0103.expensetracker

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Calendar

/**
 * The home-screen widget 本月概況: the month's spending over its budget
 * bar, this week day by day, and 支出 and 收入 at the foot. Made smaller
 * it keeps only what is left of the budget and the two buttons, one row
 * high or square. It shows what the app left in widget.json
 * (lib/src/features/overview/model/home_widget.dart) and never reads the
 * ledger. What may be shown on the home screen, locked or not, is the
 * app's decision alone: it writes only that, and the widget draws what is
 * written. With nothing written (no figures chosen in 設定 › 外觀, or
 * amounts hidden in the app) it says amounts are hidden and that a tap
 * opens the app; 支出 and 收入 open the app's composer, behind its lock.
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
            val shown = WidgetView.of(read(context), currentMonth(), today())
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

        private fun full(context: Context, shown: WidgetView.Shown): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.summary_widget)
            // Light or dark as the phone is now (values-night).
            val accent = context.getColor(R.color.widget_accent)
            val day = context.getColor(R.color.widget_day)
            views.setTextViewText(R.id.summary_title, shown.title)
            views.setTextViewText(R.id.summary_figure, shown.figure)
            views.setTextViewText(R.id.summary_budget, shown.budget)
            views.setTextViewText(R.id.summary_detail, shown.detail)
            views.setTextColor(R.id.summary_detail, stateColor(context, shown.state))
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
                    views.setTextColor(labels[i], if (today) accent else day)
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
            views.setTextColor(R.id.short_label, stateColor(context, shown.state))
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

        /**
         * The colour of the budget's words for [state], the id the app wrote
         * with them (status.dart): the app decides and words the state, the
         * widget only colours it.
         */
        private fun stateColor(context: Context, state: String): Int = context.getColor(
            when (state) {
                "over" -> R.color.widget_expense
                "near" -> R.color.widget_pace
                else -> R.color.widget_muted
            },
        )

        private fun visible(views: RemoteViews, id: Int, shown: Boolean) =
            views.setViewVisibility(id, if (shown) View.VISIBLE else View.GONE)

        private fun read(context: Context): WidgetView.Snapshot? = try {
            val file = File(context.filesDir, AppFiles.WIDGET)
            if (!file.exists()) null else WidgetView.parse(JSONObject(file.readText()))
        } catch (e: Exception) {
            null
        }

        /** This month on the phone's clock, as the snapshot names its own (2026-11). */
        private fun currentMonth(): String {
            val now = Calendar.getInstance()
            return "%04d-%02d".format(now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1)
        }

        /** Today on the phone's clock, as the snapshot names its days ahead (2026-11-03). */
        private fun today(): String {
            val now = Calendar.getInstance()
            return "%s-%02d".format(currentMonth(), now.get(Calendar.DAY_OF_MONTH))
        }
    }
}

/** What 本月概況 shows for a snapshot; kept apart from Android to be tested. */
internal object WidgetView {
    /**
     * A later day of the snapshot's month, as the app worked it out when
     * it wrote the snapshot (`ahead` in widget.json): the week, today's
     * place in it, the pace mark and the week's total that day with
     * nothing more recorded. This side does no calendar or pace maths.
     */
    data class Ahead(
        val week: List<Int>?,
        val today: Int,
        val pace: Int?,
        val weekTotal: String,
    )

    /** What the widget says once the snapshot's month is over (`stale`). */
    data class Stale(val title: String, val figure: String, val detail: String)

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
        val date: String = "",
        val state: String = "",
        val ahead: Map<String, Ahead> = emptyMap(),
        val stale: Stale? = null,
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
        val state: String = "",
    )

    private fun weekOf(days: JSONArray?): List<Int>? =
        if (days == null || days.length() != 7) null else List(7) { days.optInt(it, -1) }

    /** A snapshot as the app wrote it; one from before the week, the days ahead or the words were added still reads. */
    fun parse(json: JSONObject): Snapshot {
        val title = json.optString("title")
        val figure = json.optString("figure")
        val ahead = mutableMapOf<String, Ahead>()
        json.optJSONObject("ahead")?.let { days ->
            for (day in days.keys()) {
                val shown = days.optJSONObject(day) ?: continue
                ahead[day] = Ahead(
                    week = weekOf(shown.optJSONArray("week")),
                    today = shown.optInt("today", -1),
                    pace = if (shown.isNull("pace")) null else shown.optInt("pace"),
                    weekTotal = shown.optString("weekTotal"),
                )
            }
        }
        val stale = json.optJSONObject("stale")?.let {
            Stale(it.optString("title"), it.optString("figure"), it.optString("detail"))
        }
        return Snapshot(
            month = json.optString("month"),
            title = title,
            figure = figure,
            detail = json.optString("detail"),
            progress = if (json.isNull("progress")) null else json.optInt("progress"),
            budget = json.optString("budget"),
            pace = if (json.isNull("pace")) null else json.optInt("pace"),
            week = weekOf(json.optJSONArray("week")),
            weekTotal = json.optString("weekTotal"),
            today = json.optInt("today", -1),
            shortLabel = json.optString("shortLabel", title),
            shortFigure = json.optString("shortFigure", figure),
            date = json.optString("date"),
            state = json.optString("state"),
            ahead = ahead,
            stale = stale,
        )
    }

    /**
     * The snapshot as it stands in [month] on [today] (2026-11-03): one
     * from an earlier month says to open the app rather than show last
     * month's figures as this one's, in the words the app gave it. On a
     * later day than it was written, the week, its total and the pace
     * mark are those the app worked out for that day ([Snapshot.ahead]);
     * a day it did not work out (the clock turned back) shows it as
     * written.
     */
    fun of(snapshot: Snapshot?, month: String, today: String? = null): Shown {
        // No snapshot: the app keeps none while no figure may be shown
        // (none chosen, or amounts hidden in the app). The widget says so,
        // and that a tap opens the app, rather than look empty.
        if (snapshot == null) {
            return Shown(
                NativeWords.WIDGET_HIDDEN_TITLE, NativeWords.WIDGET_HIDDEN, NativeWords.WIDGET_HIDDEN_OPEN, null,
                shortLabel = NativeWords.WIDGET_HIDDEN, shortFigure = NativeWords.WIDGET_HIDDEN_OPEN,
            )
        }
        if (snapshot.month != month) {
            val stale = snapshot.stale ?: Stale(
                NativeWords.WIDGET_STALE_TITLE,
                NativeWords.WIDGET_STALE_FIGURE,
                NativeWords.WIDGET_STALE_DETAIL,
            )
            return Shown(stale.title, stale.figure, stale.detail, null)
        }
        val ahead = today?.let { snapshot.ahead[it] }
        return Shown(
            title = snapshot.title,
            figure = snapshot.figure,
            detail = snapshot.detail,
            progress = snapshot.progress?.coerceIn(0, 100),
            budget = snapshot.budget,
            pace = (if (ahead != null) ahead.pace else snapshot.pace)?.coerceIn(0, 100),
            week = if (ahead != null) ahead.week else snapshot.week,
            weekTotal = ahead?.weekTotal ?: snapshot.weekTotal,
            today = ahead?.today ?: snapshot.today,
            shortLabel = snapshot.shortLabel,
            shortFigure = snapshot.shortFigure,
            state = snapshot.state,
        )
    }
}
