package io.github.swz0103.expensetracker

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The worked example of the vault's inbox test (inbox_test.dart),
 * worked out with Python's `cryptography`: this side seals it the same.
 */
class InboxWriterTest {
    private fun bytes(text: String) = java.util.Base64.getDecoder().decode(text)

    @Test
    fun sealsTheWorkedExampleTheSame() {
        val item = InboxWriter.seal(
            inboxPublic = bytes("B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9/AsrhtHHw="),
            plain = "{\"kind\":\"confirm\",\"recurring\":\"r1\",\"day\":\"2026-10-05\"}"
                .toByteArray(Charsets.UTF_8),
            itemPrivate = bytes("ZWZnaGlqa2xtbm9wcXJzdHV2d3h5ent8fX5/gIGCg4Q="),
            nonce = bytes("ycrLzM3Oz9DR0tPU"),
        )
        assertEquals(
            "{\"v\":1,\"e\":\"VxR2nRFr92Q2rnS8eT0sMK0ZA8WaxSc4BcfiaYtBDDY=\"," +
                "\"n\":\"ycrLzM3Oz9DR0tPU\",\"c\":\"HtcnNKNt1m7fmuETvVKWVJ3vZ/vHeIkMg/P2uPSSG9B9" +
                "+le7i4vK/y4ynueKJGtErAxwnhvKL8EPCyzdLwQ5gAkm+vGCSw==\"}",
            item,
        )
    }

    @Test
    fun base64RoundTrips() {
        for (size in 0..40) {
            val data = ByteArray(size) { (it * 37 + 11).toByte() }
            val text = InboxWriter.base64(data)
            assertEquals(java.util.Base64.getEncoder().encodeToString(data), text)
            assertArrayEquals(data, InboxWriter.decodeBase64(text))
        }
    }
}
