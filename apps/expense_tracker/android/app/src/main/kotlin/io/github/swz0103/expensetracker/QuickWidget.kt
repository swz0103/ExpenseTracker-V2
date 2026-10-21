package io.github.swz0103.expensetracker

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

/** The home-screen widget: 記支出 and 記收入 open the composer at once. */
class QuickWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = RemoteViews(context.packageName, R.layout.quick_widget)
        views.setOnClickPendingIntent(R.id.widget_expense, MainActivity.opening(context, "expense", 1))
        views.setOnClickPendingIntent(R.id.widget_income, MainActivity.opening(context, "income", 2))
        views.setOnClickPendingIntent(R.id.widget_icon, MainActivity.opening(context, "", 3))
        for (id in ids) manager.updateAppWidget(id, views)
    }
}
