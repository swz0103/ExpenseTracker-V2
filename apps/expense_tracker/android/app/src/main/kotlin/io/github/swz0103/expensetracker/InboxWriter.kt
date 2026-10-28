package io.github.swz0103.expensetracker

import android.content.Context
import com.google.crypto.tink.subtle.Hkdf
import com.google.crypto.tink.subtle.X25519
import java.io.File
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Writes into the ledger's inbox while it is locked
 * (infrastructure/vault/lib/src/backup_security/inbox.dart): an item is
 * sealed for the inbox's public key, `inbox.pub` beside the ledger, so
 * only the open ledger can read it; this side never can.
 *
 * A new X25519 key pair for each item; the shared secret through
 * HKDF-SHA256 (salted with the item's public key, then the inbox's) to an
 * AES-256-GCM key, with "ExpenseTracker inbox v1" as both the HKDF info
 * and the associated data. One JSON file per item in `inbox/`, written
 * beside and renamed into place.
 */
object InboxWriter {
    private val INFO = "ExpenseTracker inbox v1".toByteArray(Charsets.UTF_8)
    private val random = SecureRandom()

    /**
     * [plain] sealed for [inboxPublic]; the item's key and nonce are new
     * unless given, for the test that checks the worked example.
     */
    fun seal(
        inboxPublic: ByteArray,
        plain: ByteArray,
        itemPrivate: ByteArray = X25519.generatePrivateKey(),
        nonce: ByteArray = ByteArray(12).also { random.nextBytes(it) },
    ): String {
        require(inboxPublic.size == 32 && nonce.size == 12)
        val itemPublic = X25519.publicFromPrivate(itemPrivate)
        val shared = X25519.computeSharedSecret(itemPrivate, inboxPublic)
        val key = Hkdf.computeHkdf("HMACSHA256", shared, itemPublic + inboxPublic, INFO, 32)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(INFO)
        val sealed = cipher.doFinal(plain)
        // Base64 holds no character JSON would need to escape.
        return "{\"v\":1,\"e\":\"${base64(itemPublic)}\",\"n\":\"${base64(nonce)}\"," +
            "\"c\":\"${base64(sealed)}\"}"
    }

    /**
     * Seals [plain] for the ledger kept in the app's files and puts it in
     * the inbox. False when there is no inbox key yet (the ledger has not
     * been opened since this version was installed).
     */
    fun post(context: Context, plain: ByteArray): Boolean {
        val publicFile = File(context.filesDir, "inbox.pub")
        if (!publicFile.exists()) return false
        val public = decodeBase64(publicFile.readText().trim()) ?: return false
        if (public.size != 32) return false
        val folder = File(context.filesDir, "inbox").apply { mkdirs() }
        val name = "${System.currentTimeMillis()}-${random.nextInt(1 shl 30)}.json"
        val next = File(folder, "$name.new")
        next.writeText(seal(public, plain))
        return next.renameTo(File(folder, name))
    }

    private const val ALPHABET =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    /** Standard base64 with padding, the same on a phone of any age. */
    fun base64(bytes: ByteArray): String {
        val out = StringBuilder((bytes.size + 2) / 3 * 4)
        var i = 0
        while (i < bytes.size) {
            val b0 = bytes[i].toInt() and 0xff
            val b1 = if (i + 1 < bytes.size) bytes[i + 1].toInt() and 0xff else 0
            val b2 = if (i + 2 < bytes.size) bytes[i + 2].toInt() and 0xff else 0
            out.append(ALPHABET[b0 shr 2])
            out.append(ALPHABET[((b0 and 3) shl 4) or (b1 shr 4)])
            out.append(if (i + 1 < bytes.size) ALPHABET[((b1 and 15) shl 2) or (b2 shr 6)] else '=')
            out.append(if (i + 2 < bytes.size) ALPHABET[b2 and 63] else '=')
            i += 3
        }
        return out.toString()
    }

    /** Standard base64 back to bytes; null when it is not. */
    fun decodeBase64(text: String): ByteArray? {
        if (text.length % 4 != 0) return null
        val out = java.io.ByteArrayOutputStream(text.length / 4 * 3)
        var i = 0
        while (i < text.length) {
            val values = IntArray(4)
            var pad = 0
            for (j in 0 until 4) {
                val c = text[i + j]
                if (c == '=') {
                    pad++
                    values[j] = 0
                } else {
                    if (pad > 0) return null
                    values[j] = ALPHABET.indexOf(c).takeIf { it >= 0 } ?: return null
                }
            }
            val n = (values[0] shl 18) or (values[1] shl 12) or (values[2] shl 6) or values[3]
            out.write(n shr 16)
            if (pad < 2) out.write((n shr 8) and 0xff)
            if (pad < 1) out.write(n and 0xff)
            i += 4
        }
        return out.toByteArray()
    }
}
