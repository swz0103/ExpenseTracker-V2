package io.github.swz0103.expensetracker

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Review 21 finding 7: the data transport the code scanner's libraries
 * bring is taken out of the merged manifest, so no usage report is sent.
 */
class TelemetryManifestTest {
    @Test
    fun theDataTransportComponentsAreRemoved() {
        val manifest = File("src/main/AndroidManifest.xml").readText()
        for (component in listOf(
            "com.google.android.datatransport.runtime.backends.TransportBackendDiscovery",
            "com.google.android.datatransport.runtime.scheduling.jobscheduling.JobInfoSchedulerService",
            "com.google.android.datatransport.runtime.scheduling.jobscheduling.AlarmManagerSchedulerBroadcastReceiver",
        )) {
            val node = manifest.substringAfter("android:name=\"$component\"").substringBefore("/>")
            assertTrue(component, node.contains("tools:node=\"remove\""))
        }
    }
}
