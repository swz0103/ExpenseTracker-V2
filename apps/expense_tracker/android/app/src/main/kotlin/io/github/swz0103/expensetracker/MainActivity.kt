package io.github.swz0103.expensetracker

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.view.WindowManager
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.ClearTokenRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.Scope
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Hosts the app and answers `expense_tracker/platform` (lib/src/platform.dart):
 * the private files folder; a Keystore AES key that only a fingerprint or face
 * can use, which wraps the ledger key for unlocking without the password; and
 * the system's save and open dialogs, for taking backups out and back in;
 * notifications, receipt photos, and the shortcuts and widget that open the
 * composer.
 */
class MainActivity : FlutterFragmentActivity() {
    private var pendingExport: Pair<String, MethodChannel.Result>? = null
    private var pendingPick: MethodChannel.Result? = null
    private var pendingCalendar: MethodChannel.Result? = null
    private var pendingNotify: MethodChannel.Result? = null
    private var pendingPhoto: MethodChannel.Result? = null
    private var pendingDrive: MethodChannel.Result? = null
    private var channel: MethodChannel? = null

    /** What a shortcut, the widget or a notification asked for, until taken. */
    private var pendingQuick: String? = null

    /**
     * Whether Dart has taken the action the app opened with
     * (`takeQuickAction`); its handler is listening from then on, so later
     * actions are sent to it rather than kept.
     */
    private var dartTakes = false

    /** Whether this activity is being restored rather than opened afresh. */
    private var restored = false

    /** Asks once to post notifications (Android 13 and later). */
    private val askNotify =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            val result = pendingNotify ?: return@registerForActivityResult
            pendingNotify = null
            result.success(granted && Reminders.allowed(this))
        }

    /** Where the camera writes before the photo is made smaller. */
    private val cameraFile: File
        get() = File(cacheDir, "camera").apply { mkdirs() }.resolve("receipt.jpg")

    // When the app was closed while the camera or picker was open, nothing
    // waits for the photo any more (pendingPhoto is null): it is dropped
    // rather than left in the cache.
    private val takePicture =
        registerForActivityResult(ActivityResultContracts.TakePicture()) { taken ->
            if (taken && pendingPhoto != null) {
                keepPhoto(Uri.fromFile(cameraFile))
            } else {
                cameraFile.delete()
                finishPhoto(null)
            }
        }

    private val pickImage =
        registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
            if (uri != null && pendingPhoto != null) keepPhoto(uri) else finishPhoto(null)
        }

    /** Google's consent screen for the app's own files on Drive. */
    private val askDrive =
        registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { outcome ->
            val result = pendingDrive ?: return@registerForActivityResult
            pendingDrive = null
            try {
                val granted = Identity.getAuthorizationClient(this)
                    .getAuthorizationResultFromIntent(outcome.data)
                result.success(granted.accessToken)
            } catch (e: ApiException) {
                // Closed by the person, or refused.
                result.success(null)
            }
        }

    /**
     * An access token for the files this app made on Google Drive
     * (`drive.file`). With [interactive] Google may show its account and
     * consent screens; without, a token comes only when already granted,
     * and null otherwise.
     */
    private fun driveToken(interactive: Boolean, result: MethodChannel.Result) {
        if (pendingDrive != null) {
            result.error("busy", "Already asking Google.", null)
            return
        }
        val request = AuthorizationRequest.builder()
            .setRequestedScopes(listOf(Scope(DRIVE_SCOPE)))
            .build()
        pendingDrive = result
        Identity.getAuthorizationClient(this).authorize(request)
            .addOnSuccessListener { granted: AuthorizationResult ->
                val pending = granted.pendingIntent
                if (!granted.hasResolution()) {
                    finishDrive(granted.accessToken)
                } else if (!interactive || pending == null) {
                    finishDrive(null)
                } else {
                    askDrive.launch(IntentSenderRequest.Builder(pending.intentSender).build())
                }
            }
            .addOnFailureListener { e ->
                val waiting = pendingDrive ?: return@addOnFailureListener
                pendingDrive = null
                val code = (e as? ApiException)?.statusCode?.toString() ?: "drive"
                waiting.error(code, e.message, null)
            }
    }

    private fun finishDrive(token: String?) {
        val result = pendingDrive ?: return
        pendingDrive = null
        result.success(token)
    }

    private fun finishPhoto(name: String?) {
        val result = pendingPhoto ?: return
        pendingPhoto = null
        result.success(name)
    }

    /**
     * Makes a receipt photo ready to keep: turned upright, at most 1600
     * pixels on its long side, as a JPEG in the cache. The app seals it
     * into the private `receipts` folder and deletes this copy. Off the
     * main thread.
     */
    private fun keepPhoto(source: Uri) {
        Thread {
            try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                contentResolver.openInputStream(source)?.use {
                    BitmapFactory.decodeStream(it, null, bounds)
                }
                var sample = 1
                while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1600) sample *= 2
                val decoded = contentResolver.openInputStream(source)?.use {
                    BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
                } ?: throw IllegalStateException("The photo cannot be read.")
                // Cameras save sideways and note the turn in the EXIF tags.
                val turn = if (Build.VERSION.SDK_INT < 24) {
                    0f
                } else {
                    contentResolver.openInputStream(source)?.use {
                        when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)) {
                            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                            else -> 0f
                        }
                    } ?: 0f
                }
                val longSide = maxOf(decoded.width, decoded.height)
                val scale = if (longSide > 1600) 1600f / longSide else 1f
                val matrix = Matrix().apply {
                    postScale(scale, scale)
                    postRotate(turn)
                }
                val photo = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
                val ready = File(cacheDir, "receipt-ready.jpg")
                ready.outputStream().use { photo.compress(Bitmap.CompressFormat.JPEG, 82, it) }
                cameraFile.delete()
                runOnUiThread { finishPhoto(ready.absolutePath) }
            } catch (e: Throwable) {
                // Any failure, running out of memory on a huge photo
                // included, ends the request, so takePhoto is not left busy.
                runOnUiThread {
                    val result = pendingPhoto
                    pendingPhoto = null
                    result?.error("photo", e.message, null)
                }
            }
        }.start()
    }

    /**
     * Takes the shortcut or widget action out of [intent], so it runs once.
     * An intent reopened from the recent-apps list still carries the extra
     * of its first launch, which was already acted on: it is ignored.
     */
    private fun quickOf(intent: Intent?): String? {
        val quick = intent?.getStringExtra(EXTRA_QUICK) ?: return null
        intent.removeExtra(EXTRA_QUICK)
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return null
        return quick
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Set before the engine is configured (during super.onCreate).
        restored = savedInstanceState != null
        super.onCreate(savedInstanceState)
    }

    /**
     * Each action reaches Dart exactly once. Until Dart has called
     * `takeQuickAction` (its handler is set just before), the newest action
     * is kept for that call; afterwards each one is sent as `quickAction`
     * and not kept.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val quick = quickOf(intent) ?: return
        val methods = channel
        if (dartTakes && methods != null) {
            methods.invokeMethod("quickAction", quick)
        } else {
            pendingQuick = quick
        }
    }

    /** Asks once for the calendar, where the ledger's due dates go. */
    private val askCalendar =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
            val result = pendingCalendar ?: return@registerForActivityResult
            pendingCalendar = null
            result.success(granted.values.all { it })
        }

    private fun calendarGranted(): Boolean = CALENDAR_PERMISSIONS.all {
        ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Copies a backup to where the person chooses: Downloads, Drive, ...
     * Off the main thread, as a backup with photos can be large and the
     * place a slow provider.
     */
    private val createDocument =
        registerForActivityResult(
            ActivityResultContracts.CreateDocument("application/octet-stream"),
        ) { uri ->
            val (source, result) = pendingExport ?: return@registerForActivityResult
            pendingExport = null
            if (uri == null) {
                result.success(false)
                return@registerForActivityResult
            }
            Thread {
                try {
                    val output = contentResolver.openOutputStream(uri)
                        ?: throw IllegalStateException("The chosen place cannot be written.")
                    output.use { File(source).inputStream().use { input -> input.copyTo(it) } }
                    runOnUiThread { result.success(true) }
                } catch (e: Exception) {
                    runOnUiThread { result.error("export", e.message, null) }
                }
            }.start()
        }

    /**
     * Copies the chosen file into the cache, where the app can read it; the
     * app deletes the copy once read (and at the next start, if it is
     * left). Off the main thread.
     */
    private val openDocument =
        registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            val result = pendingPick ?: return@registerForActivityResult
            pendingPick = null
            if (uri == null) {
                result.success(null)
                return@registerForActivityResult
            }
            Thread {
                try {
                    val input = contentResolver.openInputStream(uri)
                        ?: throw IllegalStateException("The chosen file cannot be read.")
                    val copy = File(cacheDir, "restore.etbk")
                    input.use { copy.outputStream().use { output -> it.copyTo(output) } }
                    runOnUiThread { result.success(copy.absolutePath) }
                } catch (e: Exception) {
                    runOnUiThread { result.error("pick", e.message, null) }
                }
            }.start()
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // A new engine runs Dart afresh, which takes the action once more.
        dartTakes = false
        // A restored activity's intent is the one already acted on.
        val opening = quickOf(intent)
        if (!restored) opening?.let { pendingQuick = it }
        val methods = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = methods
        methods
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeQuickAction" -> {
                        result.success(pendingQuick)
                        pendingQuick = null
                        dartTakes = true
                    }
                    "notificationAccess" -> {
                        if (Reminders.allowed(this)) {
                            result.success(true)
                        } else if (Build.VERSION.SDK_INT < 33) {
                            // Turned off in the system settings: only the
                            // person can turn it back on there.
                            result.success(false)
                        } else if (pendingNotify != null) {
                            result.error("busy", "Already asking.", null)
                        } else {
                            pendingNotify = result
                            askNotify.launch(Manifest.permission.POST_NOTIFICATIONS)
                        }
                    }
                    "scheduleNotifications" -> {
                        val alerts = call.argument<List<Map<String, Any?>>>("alerts")
                        if (alerts == null) {
                            result.error("bad-arguments", "alerts are required", null)
                        } else {
                            Reminders.replace(this, alerts)
                            result.success(null)
                        }
                    }
                    "takePhoto" -> {
                        if (pendingPhoto != null) {
                            result.error("busy", "A photo is being taken.", null)
                        } else {
                            pendingPhoto = result
                            if (call.argument<Boolean>("camera") == true) {
                                val uri = FileProvider.getUriForFile(this, "$packageName.files", cameraFile)
                                takePicture.launch(uri)
                            } else {
                                pickImage.launch("image/*")
                            }
                        }
                    }
                    "filesDir" -> result.success(filesDir.absolutePath)
                    "cacheDir" -> result.success(cacheDir.absolutePath)
                    "canUseBiometrics" -> result.success(
                        BiometricManager.from(this).canAuthenticate(BIOMETRIC_STRONG) ==
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
                    "exportFile" -> {
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("name")
                        if (pendingExport != null) {
                            result.error("busy", "A file is being saved.", null)
                        } else if (path == null || name == null) {
                            result.error("bad-arguments", "path and name are required", null)
                        } else {
                            pendingExport = path to result
                            createDocument.launch(name)
                        }
                    }
                    "calendarAccess" -> {
                        if (calendarGranted()) {
                            result.success(true)
                        } else if (pendingCalendar != null) {
                            result.error("busy", "Already asking.", null)
                        } else {
                            pendingCalendar = result
                            askCalendar.launch(CALENDAR_PERMISSIONS)
                        }
                    }
                    "calendars" -> {
                        if (!calendarGranted()) {
                            result.error("no-access", "Calendar access was not given.", null)
                        } else {
                            result.success(CalendarBridge.calendars(contentResolver))
                        }
                    }
                    "replaceCalendarEvents" -> {
                        val calendar = (call.argument<Any>("calendar") as? Number)?.toLong()
                        val from = (call.argument<Any>("from") as? Number)?.toLong()
                        val events = call.argument<List<Map<String, Any?>>>("events")
                        if (!calendarGranted()) {
                            result.error("no-access", "Calendar access was not given.", null)
                        } else if (calendar == null || from == null || events == null) {
                            result.error("bad-arguments", "calendar, from and events are required", null)
                        } else {
                            // Off the main thread: a calendar provider can be slow.
                            Thread {
                                try {
                                    val written = CalendarBridge.replace(contentResolver, calendar, from, events)
                                    runOnUiThread { result.success(written) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("calendar", e.message, null) }
                                }
                            }.start()
                        }
                    }
                    "secureScreen" -> {
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    "pickFile" -> {
                        if (pendingPick != null) {
                            result.error("busy", "A file is being chosen.", null)
                        } else {
                            pendingPick = result
                            openDocument.launch(arrayOf("*/*"))
                        }
                    }
                    "driveToken" -> driveToken(call.argument<Boolean>("interactive") == true, result)
                    "clearDriveToken" -> {
                        val token = call.argument<String>("token")
                        if (token == null) {
                            result.error("bad-arguments", "token is required", null)
                        } else {
                            Identity.getAuthorizationClient(this)
                                .clearToken(ClearTokenRequest.builder().setToken(token).build())
                                .addOnCompleteListener { result.success(null) }
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
        val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this), callback)
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

    companion object {
        /**
         * The intent extra of a shortcut (res/xml/shortcuts.xml), the widget
         * or a notification.
         */
        const val EXTRA_QUICK = "quick"

        /**
         * Opens the app, and the composer when [quick] names one (`expense`,
         * `income`); [code] keeps each one's PendingIntent apart.
         */
        fun opening(context: Context, quick: String, code: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (quick.isNotEmpty()) intent.putExtra(EXTRA_QUICK, quick)
            return PendingIntent.getActivity(
                context,
                code,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private const val CHANNEL = "expense_tracker/platform"
        private const val DRIVE_SCOPE = "https://www.googleapis.com/auth/drive.file"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val ALIAS = "ledger-device-key"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_BYTES = 12
        private const val TAG_BITS = 128
        private val CALENDAR_PERMISSIONS = arrayOf(
            Manifest.permission.READ_CALENDAR,
            Manifest.permission.WRITE_CALENDAR,
        )
    }
}
