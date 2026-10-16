package io.github.swz0103.expensetracker

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Hosts the app and answers `expense_tracker/platform` (lib/src/platform.dart):
 * the private files folder, and a Keystore AES key that only a fingerprint or
 * face can use, which wraps the ledger key for unlocking without the password.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "filesDir" -> result.success(filesDir.absolutePath)
                    "canUseBiometrics" -> result.success(
                        BiometricManager.from(this).canAuthenticate(BIOMETRIC_STRONG) ==
                            BiometricManager.BIOMETRIC_SUCCESS,
                    )
                    "wrap", "unwrap" -> {
                        val data = call.argument<ByteArray>("data")
                        val context = call.argument<ByteArray>("context")
                        if (data == null || context == null) {
                            result.error("bad-arguments", "data and context are required", null)
                        } else {
                            crypt(call.method == "wrap", data, context, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
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
                val iv = GCMParameterSpec(TAG_BITS, data.copyOfRange(0, IV_BYTES))
                cipher.init(Cipher.DECRYPT_MODE, key(), iv)
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
                result.error("cancelled", message.toString(), null)
            }
        }
        val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this), callback)
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(if (encrypt) "啟用指紋解鎖" else "解鎖記帳本")
            .setNegativeButtonText("改用密碼")
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    /** The Keystore key, made the first time; every use needs a confirmation. */
    private fun key(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
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
        const val CHANNEL = "expense_tracker/platform"
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "ledger-device-key"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }
}
