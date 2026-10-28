package io.github.swz0103.expensetracker

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the app and answers `expense_tracker/platform`
 * (lib/src/app/android/), one [ChannelPart] per concern: the Keystore
 * key for fingerprint unlock, receipt photos, files and the save and open
 * dialogs, the calendar, notifications and Google Drive. This class keeps
 * only what belongs to the activity itself: hiding the screen, and the
 * shortcuts, widget and notifications that open the composer.
 */
class MainActivity : FlutterFragmentActivity() {
    // Made with the activity: each registers its activity results now.
    private val parts: List<ChannelPart> = listOf(
        KeystorePart(this),
        PhotosPart(this),
        FilesPart(this),
        CalendarPart(this),
        RemindersPart(this),
        DrivePart(this),
        NetworkPart(this),
        FolderPart(this),
        BackupsPart(this),
        WidgetsPart(this),
        UpdatePart(this),
    )
    private var channel: MethodChannel? = null

    /** What a shortcut, the widget or a notification asked for, until taken. */
    private var pendingQuick: String? = null

    /**
     * Whether Dart has taken the action the app opened with
     * (`takeQuickAction`); its handler is listening from then on, so later
     * actions are sent to it rather than kept.
     */
    private var dartTakes = false

    /** Whether this activity is being restored rather than opened afresh. */
    private var restored = false

    /**
     * Takes the shortcut or widget action out of [intent], so it runs once.
     * An intent reopened from the recent-apps list still carries the extra
     * of its first launch, which was already acted on: it is ignored.
     */
    private fun quickOf(intent: Intent?): String? {
        val quick = intent?.getStringExtra(EXTRA_QUICK) ?: return null
        intent.removeExtra(EXTRA_QUICK)
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return null
        return quick
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Set before the engine is configured (during super.onCreate).
        restored = savedInstanceState != null
        super.onCreate(savedInstanceState)
    }

    /**
     * Each action reaches Dart exactly once. Until Dart has called
     * `takeQuickAction` (its handler is set just before), the newest action
     * is kept for that call; afterwards each one is sent as `quickAction`
     * and not kept.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val quick = quickOf(intent) ?: return
        val methods = channel
        if (dartTakes && methods != null) {
            methods.invokeMethod("quickAction", quick)
        } else {
            pendingQuick = quick
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // A new engine runs Dart afresh, which takes the action once more.
        dartTakes = false
        // A restored activity's intent is the one already acted on.
        val opening = quickOf(intent)
        if (!restored) opening?.let { pendingQuick = it }
        val methods = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = methods
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeQuickAction" -> {
                    result.success(pendingQuick)
                    pendingQuick = null
                    dartTakes = true
                }
                "secureScreen" -> {
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> if (parts.none { it.handle(call, result) }) result.notImplemented()
            }
        }
    }

    companion object {
        /**
         * The intent extra of a shortcut (res/xml/shortcuts.xml), the widget
         * or a notification.
         */
        const val EXTRA_QUICK = "quick"

        /**
         * Opens the app, and the composer when [quick] names one (`expense`,
         * `income`); [code] keeps each one's PendingIntent apart.
         */
        fun opening(context: Context, quick: String, code: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (quick.isNotEmpty()) intent.putExtra(EXTRA_QUICK, quick)
            return PendingIntent.getActivity(
                context,
                code,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        private const val CHANNEL = "expense_tracker/platform"
    }
}
