package io.github.swz0103.expensetracker

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/** The SHA-256 the installer checks is written as sha256sum writes it. */
class UpdateCheckTest {
    @Test
    fun hashIsTheSameAsSha256sum() {
        val file = File.createTempFile("update", ".apk")
        try {
            file.writeText("abc")
            assertEquals(
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                UpdateCheck.sha256(file),
            )
        } finally {
            file.delete()
        }
    }
}
