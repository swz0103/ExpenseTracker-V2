package dev.expensetracker.preview

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

internal object PriceAlertNotifier {
    private const val channelId = "expense_v2_price_alerts_v1"

    fun canNotify(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        ensureChannel(manager)
        return manager.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 26 ||
                manager.getNotificationChannel(channelId)?.importance != NotificationManager.IMPORTANCE_NONE)
    }

    fun deliver(
        context: Context,
        alertId: String,
        symbol: String,
        price: String,
        currency: String,
    ): Boolean {
        if (!canNotify(context)) return false
        require(alertId.length <= 64 && symbol.matches(Regex("^[A-Za-z0-9._-]{1,32}$")))
        require(price.matches(Regex("^[0-9]{1,20}(\\.[0-9]{1,12})?$")))
        require(currency.matches(Regex("^[A-Z]{3}$")))
        val notificationId = alertId.hashCode()
        val open = PendingIntent.getActivity(
            context,
            notificationId,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(context, channelId) else Notification.Builder(context)
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("$symbol 到價提醒")
            .setContentText("目前參考價 $price $currency")
            .setContentIntent(open)
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_SECRET)
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(notificationId, notification)
        return true
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(channelId, "投資到價提醒", NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
    }
}
