package io.github.swz0103.expensetracker

import androidx.biometric.BiometricPrompt
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec

/**
 * The shape of what [KeystoreHandler] hands the app: the 12-byte AES-GCM
 * IV followed by the ciphertext, with the caller's context bound in as
 * associated data. Kept apart from the Keystore so it can be tested on
 * any JVM key.
 */
object DeviceKeyBlob {
    const val TRANSFORMATION = "AES/GCM/NoPadding"
    const val IV_BYTES = 12
    const val TAG_BITS = 128

    /** The IV at the head of [blob], or null when it is too short to hold one. */
    fun ivOf(blob: ByteArray): GCMParameterSpec? =
        if (blob.size <= IV_BYTES) null else GCMParameterSpec(TAG_BITS, blob.copyOfRange(0, IV_BYTES))

    /** Seals [data] with a cipher made ready to encrypt. */
    fun seal(cipher: Cipher, data: ByteArray, context: ByteArray): ByteArray {
        cipher.updateAAD(context)
        return cipher.iv + cipher.doFinal(data)
    }

    /** Opens [blob] with a cipher made ready, with its IV, to decrypt. */
    fun open(cipher: Cipher, blob: ByteArray, context: ByteArray): ByteArray {
        cipher.updateAAD(context)
        return cipher.doFinal(blob, IV_BYTES, blob.size - IV_BYTES)
    }

    /**
     * The app's word for a prompt that ended without a fingerprint:
     * "declined" only when the person turned it down themselves.
     */
    fun refusal(code: Int): String =
        if (code == BiometricPrompt.ERROR_USER_CANCELED || code == BiometricPrompt.ERROR_NEGATIVE_BUTTON) {
            "declined"
        } else {
            "cancelled"
        }
}
