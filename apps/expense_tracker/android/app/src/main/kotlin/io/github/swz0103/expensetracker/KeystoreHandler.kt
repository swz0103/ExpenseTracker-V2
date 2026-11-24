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

/**
 * A Keystore AES key that only a fingerprint or face can use, which wraps
 * the ledger key for unlocking without the password; and a second one that
 * needs no confirmation, which seals the key of a ledger opened without a
 * password, so that key never lies on disk in plain form
 * (lib/src/app/android/keystore_adapter.dart).
 */
class KeystoreHandler(private val activity: FragmentActivity) : ChannelHandler {
    /**
     * The Keystore answers over binder calls, on every password-less open:
     * off the main thread, one at a time, so two first uses never make the
     * sealing key twice (AND-07). The fingerprint prompt stays on it.
     */
    private val offMain = OffMain.serial(activity)

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "canUseBiometrics" -> result.success(
                BiometricManager.from(activity).canAuthenticate(BIOMETRIC_STRONG) ==
                    BiometricManager.BIOMETRIC_SUCCESS,
            )
            "hasDeviceKey" -> offMain.answer(result, "keystore") { existingKey() != null }
            "wrap", "unwrap" -> {
                val data = call.argument<ByteArray>("data")
                val context = call.argument<ByteArray>("context")
                if (data == null || context == null) {
                    result.error("bad-arguments", "data and context are required", null)
                } else {
                    crypt(call.method == "wrap", data, context, result)
                }
            }
            "quickWrap", "quickUnwrap" -> {
                val data = call.argument<ByteArray>("data")
                val context = call.argument<ByteArray>("context")
                if (data == null || context == null) {
                    result.error("bad-arguments", "data and context are required", null)
                } else {
                    quick(call.method == "quickWrap", data, context, result)
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
            cipher = Cipher.getInstance(DeviceKeyBlob.TRANSFORMATION)
            if (encrypt) {
                cipher.init(Cipher.ENCRYPT_MODE, key())
            } else {
                val iv = DeviceKeyBlob.ivOf(data)
                if (iv == null) {
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
                    val output = if (encrypt) {
                        DeviceKeyBlob.seal(unlocked, data, context)
                    } else {
                        DeviceKeyBlob.open(unlocked, data, context)
                    }
                    result.success(output)
                } catch (e: Exception) {
                    result.error("keystore", e.message, null)
                }
            }

            override fun onAuthenticationError(code: Int, message: CharSequence) {
                result.error(DeviceKeyBlob.refusal(code), message.toString(), null)
            }
        }
        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(if (encrypt) "開啟生物辨識解鎖" else "解鎖記帳本")
            .setNegativeButtonText("改用密碼")
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    /**
     * Seals [data], or opens a blob sealed so, with the key that needs no
     * confirmation; [context] is bound in as AES-GCM associated data. The
     * blob is the 12-byte IV followed by the ciphertext ([DeviceKeyBlob]).
     */
    private fun quick(
        encrypt: Boolean,
        data: ByteArray,
        context: ByteArray,
        result: MethodChannel.Result,
    ) {
        offMain.run(
            {
                val cipher = Cipher.getInstance(DeviceKeyBlob.TRANSFORMATION)
                if (encrypt) {
                    cipher.init(Cipher.ENCRYPT_MODE, quickKey())
                    DeviceKeyBlob.seal(cipher, data, context)
                } else {
                    val iv = DeviceKeyBlob.ivOf(data)
                    val existing = existingKey(QUICK_ALIAS)
                    if (iv == null || existing == null) {
                        // The sealing key is gone.
                        null
                    } else {
                        cipher.init(Cipher.DECRYPT_MODE, existing, iv)
                        DeviceKeyBlob.open(cipher, data, context)
                    }
                }
            },
            { output ->
                if (output == null) {
                    result.error("key-invalidated", "The sealing key is gone.", null)
                } else {
                    result.success(output)
                }
            },
            { result.error("keystore", it.message, null) },
        )
    }

    /**
     * The key that seals a ledger's key without a password, made the first
     * time. It never leaves the phone's secure hardware, where there is
     * one, and needs no fingerprint: the ledger opens by itself.
     */
    private fun quickKey(): SecretKey {
        existingKey(QUICK_ALIAS)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                QUICK_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    /** The Keystore key, if there is one. */
    private fun existingKey(alias: String = ALIAS): SecretKey? {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        return store.getKey(alias, null) as? SecretKey
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
        const val QUICK_ALIAS = "ledger-quick-key"
    }
}
