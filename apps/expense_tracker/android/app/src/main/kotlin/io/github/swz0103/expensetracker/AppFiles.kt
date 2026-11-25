package io.github.swz0103.expensetracker

/**
 * The names of the app's own files and folders, as the app names them
 * (lib/src/core/platform/app_files.dart, the one owner). This side needs
 * some of them before the app runs (the background backup, the widget,
 * the photo and file pickers), and only those are here. A test there
 * holds each name here to the
 * app's (test/core/platform/app_files_test.dart), and another keeps these
 * names out of every other Kotlin file (test/rules/kotlin_literals_test.dart).
 */
internal object AppFiles {
    const val PREFERENCES = "preferences.json"
    const val WIDGET = "widget.json"
    const val OUTBOX = "outbox"
    const val OUTBOX_READY = "ready.json"
    const val OUTBOX_DELIVERED = "delivered.json"
    const val RESTORE_COPY = "restore.etbk"
    const val CAMERA = "camera"
    const val CAMERA_PHOTO = "receipt.jpg"
    const val RECEIPT_READY = "receipt-ready.jpg"
    const val RECEIPT_LEFTOVER = "receipt-leftover.jpg"
}
