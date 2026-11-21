package io.github.swz0103.expensetracker

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import org.json.JSONArray

/**
 * Where the alerts to come are kept between the app and a restart of the
 * phone: sealed with a key of the phone's Keystore that needs no
 * fingerprint, as a notification must be posted while the ledger is
 * locked. Their titles and texts can name an amount, so they are never
 * written in plain words; a copy of the preferences file read off the
 * phone shows nothing of them. Alerts kept in plain words by 0.19 and
 * earlier are read once and sealed.
 */
object ReminderStore {
    private const val PREFS = "reminders"
    private const val SEALED = "sealed"

    /** Where 0.19 and earlier kept them in plain words. */
    private const val PLAIN = "alerts"
    private const val KEYSTORE = "AndroidKeyStore"
    private const val ALIAS = "reminders"
    private val CONTEXT = "reminders".toByteArray(Charsets.UTF_8)

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** The alerts kept; none when nothing is, or it cannot be opened (the
     *  app sends them all again the next time it is opened). */
    fun read(context: Context): JSONArray {
        val prefs = prefs(context)
        val sealed = prefs.getString(SEALED, null)
        return try {
            if (sealed != null) {
                JSONArray(String(open(Base64.decode(sealed, Base64.NO_WRAP)), Charsets.UTF_8))
            } else {
                val plain = prefs.getString(PLAIN, null) ?: return JSONArray()
                JSONArray(plain).also { write(context, it) }
            }
        } catch (e: Exception) {
            JSONArray()
        }
    }

    /** Keeps [alerts], sealed, in place of what was kept before. */
    fun write(context: Context, alerts: JSONArray) {
        val sealed = seal(alerts.toString().toByteArray(Charsets.UTF_8))
        prefs(context).edit()
            .putString(SEALED, Base64.encodeToString(sealed, Base64.NO_WRAP))
            .remove(PLAIN)
            .apply()
    }

    private fun seal(data: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(DeviceKeyBlob.TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        return DeviceKeyBlob.seal(cipher, data, CONTEXT)
    }

    private fun open(blob: ByteArray): ByteArray {
        val iv = DeviceKeyBlob.ivOf(blob) ?: throw IllegalArgumentException("too short")
        val cipher = Cipher.getInstance(DeviceKeyBlob.TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), iv)
        return DeviceKeyBlob.open(cipher, blob, CONTEXT)
    }

    /** The Keystore key, made the first time; it never leaves the phone's
     *  secure hardware, where there is one. */
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
                .build(),
        )
        return generator.generateKey()
    }
}
