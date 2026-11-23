package io.github.swz0103.expensetracker

import android.app.backup.BackupAgent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * F65: Android's own backup takes the one folder the app writes its copy
 * into, on every Android version, and nothing else of the app.
 */
class BackupRulesTest {
    /** Each rule of [file] in res/xml: its section, include or exclude, domain and path. */
    private fun rules(file: String): List<String> {
        val xml = listOf("src/main/res/xml/$file", "app/src/main/res/xml/$file")
            .map(::File)
            .first { it.exists() }
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(xml)
        val found = mutableListOf<String>()
        for (tag in listOf("include", "exclude")) {
            val nodes = document.getElementsByTagName(tag)
            for (i in 0 until nodes.length) {
                val node = nodes.item(i)
                val attributes = node.attributes
                found.add(
                    "${node.parentNode.nodeName} $tag " +
                        "${attributes.getNamedItem("domain").nodeValue}:${attributes.getNamedItem("path").nodeValue}",
                )
            }
        }
        return found
    }

    @Test
    fun android12AndLaterTakeTheCloudFolderOnly() {
        assertEquals(
            listOf(
                "cloud-backup include file:${LedgerBackupAgent.FOLDER}",
                "device-transfer include file:${LedgerBackupAgent.FOLDER}",
            ),
            rules("data_extraction_rules.xml"),
        )
    }

    @Test
    fun android11AndEarlierTakeTheSameFolder() {
        assertEquals(
            listOf("full-backup-content include file:${LedgerBackupAgent.FOLDER}"),
            rules("backup_rules.xml"),
        )
    }

    @Test
    fun onlyATripToTheGoogleAccountIsWrittenDown() {
        val toPhone = BackupAgent.FLAG_DEVICE_TO_DEVICE_TRANSFER
        assertTrue(LedgerBackupAgent.forAccount(28, 0))
        assertFalse(LedgerBackupAgent.forAccount(28, toPhone))
        // Before Android 9 the two cannot be told apart: it counts.
        assertTrue(LedgerBackupAgent.forAccount(27, toPhone))
    }
}
