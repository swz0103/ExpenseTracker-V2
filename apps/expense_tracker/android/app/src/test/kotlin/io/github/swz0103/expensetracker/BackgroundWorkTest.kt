package io.github.swz0103.expensetracker

import androidx.work.NetworkType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.net.SocketTimeoutException

/** AND-05: what the background jobs cost and when a failed run is tried again. */
class BackgroundWorkTest {
    @Test
    fun theMarketsListsWaitForWiFi() {
        assertEquals(NetworkType.UNMETERED, BackgroundWork.MARKET_NETWORK)
    }

    @Test
    fun backupsNeedANetworkOnlyForDrive() {
        assertEquals(NetworkType.CONNECTED, BackgroundWork.backupNetwork(driveLinked = true))
        assertEquals(NetworkType.NOT_REQUIRED, BackgroundWork.backupNetwork(driveLinked = false))
    }

    @Test
    fun neitherRunsOnALowBattery() {
        val constraints = BackgroundWork.constraints(NetworkType.UNMETERED)
        assertTrue(constraints.requiresBatteryNotLow())
        assertEquals(NetworkType.UNMETERED, constraints.requiredNetworkType)
    }

    @Test
    fun aDroppedNetworkIsTriedAgainThreeTimesThenNoted() {
        val dropped = SocketTimeoutException("timeout")
        assertTrue(BackgroundWork.retries(dropped, 0))
        assertTrue(BackgroundWork.retries(dropped, 2))
        // The fourth failure in a row (attempt 3) is noted for the app.
        assertFalse(BackgroundWork.retries(dropped, 3))
    }

    @Test
    fun googleBusyIsTriedAgainARefusalOrNoAccessIsNot() {
        assertTrue(BackgroundWork.retries(DriveUploader.Refused(503, "503 backend"), 0))
        assertTrue(BackgroundWork.retries(DriveUploader.Refused(429, "429 rate"), 0))
        assertFalse(BackgroundWork.retries(DriveUploader.Refused(403, "403 quota"), 0))
        assertFalse(BackgroundWork.retries(DriveUploader.NotAllowed(), 0))
        assertFalse(BackgroundWork.retries(IllegalStateException("no folder"), 0))
        assertTrue(BackgroundWork.retries(IOException("reset"), 1))
    }
}
