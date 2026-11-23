package io.github.swz0103.expensetracker

import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusCodes
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate.InstallState

/**
 * Why the code scanner could not be used, as a name the app keeps in its
 * error log (lib/src/app/android/scanner_adapter.dart): capital letters and
 * underscores only, so nothing of the phone or the person can be in it.
 * Google's own names where it has one (`NETWORK_ERROR`,
 * `INSUFFICIENT_STORAGE`, `API_UNAVAILABLE`…).
 */
object ScanFault {
    /** The scanner did not arrive within [ScanHandler.FETCH_TIMEOUT_MS]. */
    const val TIMEOUT = "INSTALL_TIMEOUT"

    /** The download ended without Google saying why. */
    const val FAILED = "INSTALL_FAILED"

    /** The download was called off. */
    const val CANCELED = "INSTALL_CANCELED"

    /** A status Google has no name for. */
    const val UNNAMED = "UNNAMED_STATUS"

    private val name = Regex("^[A-Z_]+$")

    /** Google's name for the status [code] of Play services. */
    fun status(code: Int): String =
        ModuleInstallStatusCodes.getStatusCodeString(code).takeIf { name.matches(it) } ?: UNNAMED

    /** Why [error] happened: its status when Play services gave one, else its kind. */
    fun reason(error: Exception): String =
        if (error is ApiException) status(error.statusCode) else kind(error.javaClass.simpleName)

    /** `IllegalStateException` as `ILLEGAL_STATE_EXCEPTION`. */
    fun kind(className: String): String =
        className.replace(Regex("(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])"), "_").uppercase()
            .takeIf { name.matches(it) } ?: UNNAMED

    /**
     * Why a download that ended in [state] did: Google's reason [errorCode]
     * when it gave one (0 is none), else how it ended.
     */
    fun install(@InstallState state: Int, errorCode: Int): String = when {
        errorCode != 0 -> status(errorCode)
        state == InstallState.STATE_CANCELED -> CANCELED
        else -> FAILED
    }
}
