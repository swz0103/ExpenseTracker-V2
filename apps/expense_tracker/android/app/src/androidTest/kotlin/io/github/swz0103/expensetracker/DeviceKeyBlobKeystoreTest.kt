package io.github.swz0103.expensetracker

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.security.KeyStore
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * The device-key blob on the phone's own Keystore (KeystoreHandler.kt):
 * a Keystore key picks the IV itself and keeps the key in hardware, which
 * a plain JVM key does not show. The key here needs no fingerprint, so the
 * test runs unattended; the format and the cipher are the ones the app
 * uses.
 */
@RunWith(AndroidJUnit4::class)
class DeviceKeyBlobKeystoreTest {
    private val alias = "device-key-blob-test"
    private val ledgerKey = ByteArray(32) { (it * 7).toByte() }
    private val context = "ledger-device-key:v1".toByteArray()

    private fun key(): SecretKey {
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun seal(key: SecretKey, data: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(DeviceKeyBlob.TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        return DeviceKeyBlob.seal(cipher, data, context)
    }

    private fun open(key: SecretKey, blob: ByteArray, context: ByteArray = this.context): ByteArray {
        val cipher = Cipher.getInstance(DeviceKeyBlob.TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key, assertNotNullIv(blob))
        return DeviceKeyBlob.open(cipher, blob, context)
    }

    private fun assertNotNullIv(blob: ByteArray) = DeviceKeyBlob.ivOf(blob).also { assertNotNull(it) }

    @After
    fun forget() {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(alias)
    }

    @Test
    fun aKeySealedByTheKeystoreOpensAsItWas() {
        val key = key()
        assertArrayEquals(ledgerKey, open(key, seal(key, ledgerKey)))
    }

    @Test(expected = AEADBadTagException::class)
    fun anotherLedgersContextCannotOpenIt() {
        val key = key()
        open(key, seal(key, ledgerKey), "another-ledger".toByteArray())
    }

    @Test(expected = AEADBadTagException::class)
    fun aChangedByteCannotOpenIt() {
        val key = key()
        val blob = seal(key, ledgerKey)
        blob[DeviceKeyBlob.IV_BYTES + 3] = (blob[DeviceKeyBlob.IV_BYTES + 3] + 1).toByte()
        open(key, blob)
    }
}
