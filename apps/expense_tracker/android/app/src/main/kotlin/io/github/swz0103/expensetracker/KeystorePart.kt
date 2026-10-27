package io.github.swz0103.expensetracker

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * A Keystore AES key that only a fingerprint or face can use, which wraps
 * the ledger key for unlocking without the password
 * (lib/src/app/android/keystore.dart).
 */
class KeystorePart(private val activity: FragmentActivity) : ChannelPart {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "canUseBiometrics" -> result.success(
                BiometricManager.from(activity).canAuthenticate(BIOMETRIC_STRONG) ==
                    BiometricManager.BIOMETRIC_SUCCESS,
            )
            "hasDeviceKey" -> result.success(existingKey() != null)
            "wrap", "unwrap" -> {
                val data = call.argument<ByteArray>("data")
                val context = call.argument<ByteArray>("context")
                if (data == null || context == null) {
                    result.error("bad-arguments", "data and context are required", null)
                } else {
                    crypt(call.method == "wrap", data, context, result)
                }
            }
            else -> return false
        }
        return true
    }

    /**
     * Encrypts [data] or decrypts a blob made by this method once the person
     * confirms with a fingerprint or face. [context] is bound in as AES-GCM
     * associated data. A blob is the 12-byte IV followed by the ciphertext.
     */
    private fun crypt(
        encrypt: Boolean,
        data: ByteArray,
        context: ByteArray,
        result: MethodChannel.Result,
    ) {
        val cipher: Cipher
        try {
            cipher = Cipher.getInstance(TRANSFORMATION)
            if (encrypt) {
                cipher.init(Cipher.ENCRYPT_MODE, key())
            } else {
                if (data.size <= IV_BYTES) {
                    result.error("bad-blob", "The blob is too short.", null)
                    return
                }
                // Opening never makes a key: a missing one was invalidated,
                // and only a password unlock may enrol a new one.
                val existing = existingKey()
                if (existing == null) {
                    result.error("key-invalidated", "The device key is gone.", null)
                    return
                }
                val iv = GCMParameterSpec(TAG_BITS, data.copyOfRange(0, IV_BYTES))
                cipher.init(Cipher.DECRYPT_MODE, existing, iv)
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            // A fingerprint was added or removed: the key is gone for good,
            // and the next password unlock enrols a new one.
            deleteKey()
            result.error("key-invalidated", e.message, null)
            return
        } catch (e: Exception) {
            result.error("keystore", e.message, null)
            return
        }
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                val unlocked = auth.cryptoObject?.cipher
                if (unlocked == null) {
                    result.error("keystore", "No cipher after confirming.", null)
                    return
                }
                try {
                    unlocked.updateAAD(context)
                    val output = if (encrypt) {
                        unlocked.iv + unlocked.doFinal(data)
                    } else {
                        unlocked.doFinal(data, IV_BYTES, data.size - IV_BYTES)
                    }
                    result.success(output)
                } catch (e: Exception) {
                    result.error("keystore", e.message, null)
                }
            }

            override fun onAuthenticationError(code: Int, message: CharSequence) {
                // "declined" only when the person turned it down themselves.
                val declined = code == BiometricPrompt.ERROR_USER_CANCELED ||
                    code == BiometricPrompt.ERROR_NEGATIVE_BUTTON
                result.error(if (declined) "declined" else "cancelled", message.toString(), null)
            }
        }
        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(if (encrypt) "啟用指紋解鎖" else "解鎖記帳本")
            .setNegativeButtonText("改用密碼")
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    /** The Keystore key, if there is one. */
    private fun existingKey(): SecretKey? {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        return store.getKey(ALIAS, null) as? SecretKey
    }

    /** The Keystore key, made the first time; every use needs a confirmation. */
    private fun key(): SecretKey {
        existingKey()?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(true)
                .setInvalidatedByBiometricEnrollment(true)
                .build(),
        )
        return generator.generateKey()
    }

    private fun deleteKey() {
        KeyStore.getInstance(KEYSTORE).apply { load(null) }.deleteEntry(ALIAS)
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "ledger-device-key"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }
}
