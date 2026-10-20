package io.github.swz0103.expensetracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/** The home-screen widget: 記支出 and 記收入 open the composer at once. */
class QuickWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = RemoteViews(context.packageName, R.layout.quick_widget)
        views.setOnClickPendingIntent(R.id.widget_expense, open(context, "expense", 1))
        views.setOnClickPendingIntent(R.id.widget_income, open(context, "income", 2))
        views.setOnClickPendingIntent(R.id.widget_icon, open(context, "", 3))
        for (id in ids) manager.updateAppWidget(id, views)
    }

    private fun open(context: Context, quick: String, code: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (quick.isNotEmpty()) intent.putExtra(MainActivity.EXTRA_QUICK, quick)
        return PendingIntent.getActivity(
            context,
            code,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
