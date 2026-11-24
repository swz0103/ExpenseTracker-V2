package io.github.swz0103.expensetracker

import androidx.work.NetworkType
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.net.SocketTimeoutException
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeoutException

/** AND-05: what the background jobs cost and when a failed run is tried again. */
class BackgroundWorkTest {
    @Test
    fun theMarketsListsGoOnAnyNetwork() {
        // D40: any network, not Wi-Fi only.
        assertEquals(NetworkType.CONNECTED, BackgroundWork.MARKET_NETWORK)
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
    fun theMarketJobKeepsTheBatteryRuleAndTheBackOff() {
        val request = BackgroundWork.periodic(MarketWorker::class.java, 3, BackgroundWork.MARKET_NETWORK)
        assertTrue(request.workSpec.constraints.requiresBatteryNotLow())
        assertEquals(NetworkType.CONNECTED, request.workSpec.constraints.requiredNetworkType)
        assertEquals(androidx.work.BackoffPolicy.EXPONENTIAL, request.workSpec.backoffPolicy)
        // 15 minutes, in milliseconds: 15 * 60 * 1000.
        assertEquals(900000L, request.workSpec.backoffDelayDuration)
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

    @Test
    fun playServicesSlowOrOfflineIsTriedAgain() {
        // Review 21 finding 3: Tasks.await throws these, not IOException.
        assertTrue(BackgroundWork.retries(TimeoutException("60 s"), 0))
        assertTrue(BackgroundWork.retries(ExecutionException(IOException("offline")), 0))
        assertTrue(
            BackgroundWork.retries(
                ExecutionException(ApiException(Status(CommonStatusCodes.NETWORK_ERROR))),
                1,
            ),
        )
        assertTrue(BackgroundWork.retries(ApiException(Status(CommonStatusCodes.TIMEOUT)), 2))
        // Still noted after three runs in a row.
        assertFalse(BackgroundWork.retries(TimeoutException("60 s"), 3))
    }

    @Test
    fun playServicesRefusingIsNotTriedAgain() {
        assertFalse(
            BackgroundWork.retries(
                ExecutionException(ApiException(Status(CommonStatusCodes.DEVELOPER_ERROR))),
                0,
            ),
        )
        assertFalse(BackgroundWork.retries(ExecutionException(IllegalStateException("no")), 0))
    }

    @Test
    fun theFailureUnderPlayServicesWrappingIsNamed() {
        val cause = IOException("offline")
        assertEquals(cause, BackgroundWork.causeOf(ExecutionException(cause)))
        assertEquals(cause, BackgroundWork.causeOf(cause))
    }

    @Test
    fun aSecondRunWaitsWhileTheFirstIsUnderWay() {
        // Review 21 finding 2: a stopped run still finishing and the next.
        val runs = BackgroundWork.OneAtATime()
        val inner = runs.run(whenBusy = "busy") { runs.run(whenBusy = "busy") { "second" } }
        assertEquals("busy", inner)
        // Once the first is over, the next runs.
        assertEquals("ran", runs.run(whenBusy = "busy") { "ran" })
        // A run that failed frees the way too.
        try {
            runs.run(whenBusy = "busy") { throw IllegalStateException("failed") }
        } catch (e: IllegalStateException) {
            // Expected.
        }
        assertEquals("ran", runs.run(whenBusy = "busy") { "ran" })
    }
}
