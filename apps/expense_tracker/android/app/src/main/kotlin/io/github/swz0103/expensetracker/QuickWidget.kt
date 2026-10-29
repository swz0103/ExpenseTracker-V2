package io.github.swz0103.expensetracker

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context

/**
 * The widget 記一筆, kept so the ones already on home screens stay: it is
 * now 本月概況 one row high (SummaryWidget.kt), and grows into it.
 */
class QuickWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = SummaryWidget.views(context, small = true)
        for (id in ids) manager.updateAppWidget(id, views)
    }
}
