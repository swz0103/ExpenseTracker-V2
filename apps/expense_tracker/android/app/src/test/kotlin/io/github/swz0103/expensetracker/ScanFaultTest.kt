package io.github.swz0103.expensetracker

import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.Status
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate.InstallState
import org.junit.Assert.assertEquals
import org.junit.Test

/** F66: why the scanner could not be used reaches the app as a plain name. */
class ScanFaultTest {
    @Test
    fun namesAStatusOfPlayServicesAsGoogleDoes() {
        assertEquals("NETWORK_ERROR", ScanFault.status(7))
        assertEquals("API_NOT_CONNECTED", ScanFault.status(17))
        assertEquals("INSUFFICIENT_STORAGE", ScanFault.status(46003))
    }

    @Test
    fun aStatusWithoutANameCarriesNoNumber() {
        // Google answers "unknown status code: 99999", which is no name.
        assertEquals("UNNAMED_STATUS", ScanFault.status(99999))
    }

    @Test
    fun anErrorIsNamedByItsStatusOrItsKind() {
        assertEquals("NETWORK_ERROR", ScanFault.reason(ApiException(Status(7))))
        assertEquals("ILLEGAL_STATE_EXCEPTION", ScanFault.reason(IllegalStateException("/data/x")))
        assertEquals("IO_EXCEPTION", ScanFault.kind("IOException"))
        assertEquals("UNNAMED_STATUS", ScanFault.kind(""))
    }

    @Test
    fun aDownloadThatEndedSaysWhy() {
        assertEquals("INSUFFICIENT_STORAGE", ScanFault.install(InstallState.STATE_FAILED, 46003))
        assertEquals("INSTALL_FAILED", ScanFault.install(InstallState.STATE_FAILED, 0))
        assertEquals("INSTALL_CANCELED", ScanFault.install(InstallState.STATE_CANCELED, 0))
        assertEquals("INSTALL_TIMEOUT", ScanFault.TIMEOUT)
    }

    @Test
    fun theScannerIsWaitedForAMinuteAndAHalf() {
        assertEquals(90_000L, ScanHandler.FETCH_TIMEOUT_MS)
    }
}
