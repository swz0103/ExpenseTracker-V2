package io.github.swz0103.expensetracker

/**
 * The only words this side keeps: those it must show while the app cannot
 * run to hand its own over. Everywhere else the app hands the words over
 * with the call (lib/src/core/messages/native_messages.dart). A test
 * there holds each word here to the app's
 * (test/core/messages/native_messages_test.dart), and another keeps
 * Chinese text out of every other Kotlin file
 * (test/rules/kotlin_literals_test.dart).
 */
internal object NativeWords {
    /**
     * The home-screen widget with no snapshot to read (no figure may be
     * shown): `WidgetWords` in widget_messages.dart.
     */
    const val WIDGET_HIDDEN_TITLE = "記帳本"
    const val WIDGET_HIDDEN = "已隱藏金額"
    const val WIDGET_HIDDEN_OPEN = "點此打開"

    /**
     * The widget with a snapshot of an earlier month written before the
     * app handed these words over in it (`WidgetWords.stale…`).
     */
    const val WIDGET_STALE_TITLE = "本月概況"
    const val WIDGET_STALE_FIGURE = "—"
    const val WIDGET_STALE_DETAIL = "打開 App 更新本月數字"

    /**
     * A reminder kept by a version before the app handed its words over
     * with the plan, going off before the app is next opened.
     */
    const val REMINDER_CONFIRM = "確認入帳"
    const val REMINDER_PUBLIC_TITLE = "記帳本"
    const val REMINDER_PUBLIC_TEXT = "有一則提醒"

    /** A newer version noticed in the background (UpdateWorker, sideload build). */
    const val UPDATE_CHANNEL = "新版本"
    const val UPDATE_CHANNEL_ABOUT = "有新版本可以更新時"
    const val UPDATE_TITLE = "記帳本有新版本"

    /** With the version in place of `%s`. */
    const val UPDATE_TITLE_OF = "記帳本 %s 可以更新"
    const val UPDATE_TEXT = "打開 App 就能更新"
}
