package io.github.swz0103.expensetracker

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * Installs a newer version downloaded by the app
 * (lib/src/app/android/update.dart): the file is checked against the
 * SHA-256 published with it, then handed to Android's installer, where
 * the person confirms. Android installs it only when it is signed with the
 * same key, and the app's data stays.
 */
class UpdatePart(private val activity: FragmentActivity) : ChannelPart {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != "installApk") return false
        val path = call.argument<String>("path")
        val expected = call.argument<String>("sha256")
        if (path == null || expected == null) {
            result.error("bad-arguments", "path and sha256 are required", null)
            return true
        }
        Thread {
            val outcome = try {
                install(File(path), expected)
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("update", e.message, null) }
                return@Thread
            }
            activity.runOnUiThread { result.success(outcome) }
        }.start()
        return true
    }

    private fun install(apk: File, expected: String): String {
        if (!apk.exists() || UpdateCheck.sha256(apk) != expected.lowercase()) {
            apk.delete()
            return "damaged"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            activity.runOnUiThread {
                activity.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${activity.packageName}"),
                    ),
                )
            }
            return "needsPermission"
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.files", apk)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.runOnUiThread { activity.startActivity(intent) }
        return "started"
    }
}

/** The SHA-256 of a file, as hex; kept apart from Android to be tested. */
internal object UpdateCheck {
    fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
