package io.github.swz0103.expensetracker

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
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
 * (lib/src/app/android/update_adapter.dart). Before Android's installer is
 * opened, [UpdateGate] checks the file: its size against the most Dart
 * allows, the SHA-256 published with it, and, read from the APK itself,
 * that it is this app, a higher version code and signed with the same
 * certificates as the running app. Then the person confirms in the
 * installer, which installs it only when it is signed with the same key,
 * and the app's data stays.
 */
class UpdateHandler(private val activity: FragmentActivity) : ChannelHandler {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method != "installApk") return false
        val path = call.argument<String>("path")
        val expected = call.argument<String>("sha256")
        val maxBytes = call.argument<Number>("maxBytes")?.toLong()
        if (path == null || expected == null || maxBytes == null) {
            result.error("bad-arguments", "path, sha256 and maxBytes are required", null)
            return true
        }
        OffMain.of(activity).answer(result, "update") { install(File(path), expected, maxBytes) }
        return true
    }

    private fun install(apk: File, expected: String, maxBytes: Long): String {
        val manager = activity.packageManager
        val installed = PlatformApks.facts(manager, activity.packageName)
            ?: throw IllegalStateException("The installed app cannot be read.")
        val verdict = UpdateGate(installed, PlatformApks.inspector(manager), maxBytes)
            .check(apk, expected)
        if (verdict != UpdateVerdict.OK) {
            apk.delete()
            return when (verdict) {
                UpdateVerdict.TOO_LARGE, UpdateVerdict.DAMAGED, UpdateVerdict.UNREADABLE -> "damaged"
                else -> "rejected"
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !manager.canRequestPackageInstalls()) {
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

/** Reads [PackageFacts] through Android's PackageManager. */
internal object PlatformApks {
    @Suppress("DEPRECATION")
    private val flags =
        if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
        else PackageManager.GET_SIGNATURES

    fun inspector(manager: PackageManager) = ApkInspector { apk ->
        factsOf(manager.getPackageArchiveInfo(apk.path, flags))
    }

    fun facts(manager: PackageManager, packageName: String): PackageFacts? =
        factsOf(manager.getPackageInfo(packageName, flags))

    @Suppress("DEPRECATION")
    private fun factsOf(info: PackageInfo?): PackageFacts? {
        if (info == null) return null
        val certificates: Array<Signature> =
            (if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures)
                ?: emptyArray()
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        return PackageFacts(
            info.packageName ?: return null,
            code,
            certificates.map { UpdateGate.digestOf(it.toByteArray()) }.toSet(),
        )
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
