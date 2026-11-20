package io.github.swz0103.expensetracker

import androidx.biometric.BiometricPrompt
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/** The blob the fingerprint key makes, on a plain JVM key (KeystoreHandler.kt). */
class DeviceKeyBlobTest {
    private val key: SecretKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
    private val ledgerKey = ByteArray(32) { it.toByte() }
    private val context = "ledger-device-key:v1".toByteArray()

    private fun seal(data: ByteArray, context: ByteArray = this.context): ByteArray {
        val cipher = Cipher.getInstance(DeviceKeyBlob.TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        return DeviceKeyBlob.seal(cipher, data, context)
    }

    private fun open(blob: ByteArray, context: ByteArray = this.context): ByteArray {
        val cipher = Cipher.getInstance(DeviceKeyBlob.TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key, DeviceKeyBlob.ivOf(blob))
        return DeviceKeyBlob.open(cipher, blob, context)
    }

    @Test
    fun aSealedKeyOpensAsItWas() {
        val blob = seal(ledgerKey)
        assertEquals(DeviceKeyBlob.IV_BYTES + ledgerKey.size + DeviceKeyBlob.TAG_BITS / 8, blob.size)
        assertArrayEquals(ledgerKey, open(blob))
    }

    @Test
    fun everySealTakesAFreshIv() {
        val first = seal(ledgerKey)
        val second = seal(ledgerKey)
        assertTrue(!first.copyOfRange(0, 12).contentEquals(second.copyOfRange(0, 12)))
    }

    @Test(expected = AEADBadTagException::class)
    fun anotherContextCannotOpenIt() {
        open(seal(ledgerKey), "another-ledger".toByteArray())
    }

    @Test(expected = AEADBadTagException::class)
    fun aChangedByteCannotOpenIt() {
        val blob = seal(ledgerKey)
        blob[blob.size - 1] = (blob[blob.size - 1] + 1).toByte()
        open(blob)
    }

    @Test
    fun aBlobTooShortForItsIvIsRefusedBeforeAnyKey() {
        assertNull(DeviceKeyBlob.ivOf(ByteArray(DeviceKeyBlob.IV_BYTES)))
        assertNull(DeviceKeyBlob.ivOf(ByteArray(0)))
    }

    @Test
    fun onlyThePersonTurningItDownIsDeclined() {
        assertEquals("declined", DeviceKeyBlob.refusal(BiometricPrompt.ERROR_USER_CANCELED))
        assertEquals("declined", DeviceKeyBlob.refusal(BiometricPrompt.ERROR_NEGATIVE_BUTTON))
        assertEquals("cancelled", DeviceKeyBlob.refusal(BiometricPrompt.ERROR_LOCKOUT))
        assertEquals("cancelled", DeviceKeyBlob.refusal(BiometricPrompt.ERROR_TIMEOUT))
    }
}
