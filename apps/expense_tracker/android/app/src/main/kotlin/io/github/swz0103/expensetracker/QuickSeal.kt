package io.github.swz0103.expensetracker

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * The Keystore key that needs no confirmation: it seals the key of a
 * ledger opened without a password, and what of the settings could name
 * the person (KeystoreHandler.kt, `quickWrap`; lib/src/core/platform/preferences.dart),
 * so neither lies on disk in plain form. The background backup opens the
 * phone folder the app sealed for it with [FOLDER_CONTEXT].
 */
internal object QuickSeal {
    private const val KEYSTORE = "AndroidKeyStore"
    private const val ALIAS = "ledger-quick-key"

    /** What the app seals the backup folder for (`Preferences.folderContext`). */
    const val FOLDER_CONTEXT = "expense_tracker/backup-folder"

    /** [data] sealed, with [context] bound in as AES-GCM associated data ([DeviceKeyBlob]). */
    fun seal(data: ByteArray, context: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(DeviceKeyBlob.TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        return DeviceKeyBlob.seal(cipher, data, context)
    }

    /** [blob] opened, for [context]; null when the key is gone or the blob too short. */
    fun open(blob: ByteArray, context: ByteArray): ByteArray? {
        val iv = DeviceKeyBlob.ivOf(blob) ?: return null
        val existing = existing() ?: return null
        val cipher = Cipher.getInstance(DeviceKeyBlob.TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, existing, iv)
        return DeviceKeyBlob.open(cipher, blob, context)
    }

    private fun existing(): SecretKey? =
        KeyStore.getInstance(KEYSTORE).apply { load(null) }.getKey(ALIAS, null) as? SecretKey

    /**
     * The key, made the first time. It never leaves the phone's secure
     * hardware, where there is one, and needs no fingerprint.
     */
    private fun key(): SecretKey {
        existing()?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }
}
