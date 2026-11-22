package io.github.swz0103.expensetracker

import java.io.File
import java.security.MessageDigest

/** What identifies an app package: its name, version code and signers. */
internal data class PackageFacts(
    val packageName: String,
    val versionCode: Long,
    /** SHA-256 of each signing certificate, hex, lower case. */
    val signers: Set<String>,
)

/** Reads [PackageFacts] from an APK file; null when it cannot be read. */
internal fun interface ApkInspector {
    fun inspect(apk: File): PackageFacts?
}

internal enum class UpdateVerdict {
    OK,

    /** Larger than the most an update may be. */
    TOO_LARGE,

    /** Not the file whose SHA-256 was published. */
    DAMAGED,

    /** Not an APK Android can read. */
    UNREADABLE,

    /** A different app. */
    WRONG_PACKAGE,

    /** Not a newer version than the one installed. */
    NOT_NEWER,

    /** Signed with another key than the installed app's. */
    WRONG_SIGNER,
}

/**
 * Whether a downloaded APK may be handed to Android's installer. Android
 * itself refuses an APK signed with another key and a lower version, but
 * only after the person has been taken to the installer; and the
 * published SHA-256 comes from the same place as the APK. So the app asks
 * all of it first, in this order, and installs only on [UpdateVerdict.OK]:
 * the size (before reading the file), the SHA-256, then, from the APK
 * itself, the package name, a strictly higher version code, and the same
 * signing certificates as the running app. Kept apart from Android to be
 * tested: [inspector] is the only part that touches the platform.
 */
internal class UpdateGate(
    private val installed: PackageFacts,
    private val inspector: ApkInspector,
    private val maxBytes: Long,
) {
    fun check(apk: File, expectedSha256: String): UpdateVerdict {
        if (!apk.isFile) return UpdateVerdict.DAMAGED
        if (apk.length() > maxBytes) return UpdateVerdict.TOO_LARGE
        if (UpdateCheck.sha256(apk) != expectedSha256.lowercase()) return UpdateVerdict.DAMAGED
        val found = inspector.inspect(apk) ?: return UpdateVerdict.UNREADABLE
        if (found.packageName != installed.packageName) return UpdateVerdict.WRONG_PACKAGE
        if (found.versionCode <= installed.versionCode) return UpdateVerdict.NOT_NEWER
        if (found.signers.isEmpty() || found.signers != installed.signers) {
            return UpdateVerdict.WRONG_SIGNER
        }
        return UpdateVerdict.OK
    }

    companion object {
        /** The SHA-256 of a certificate's encoded bytes, as hex. */
        fun digestOf(certificate: ByteArray): String =
            MessageDigest.getInstance("SHA-256").digest(certificate)
                .joinToString("") { "%02x".format(it) }
    }
}
