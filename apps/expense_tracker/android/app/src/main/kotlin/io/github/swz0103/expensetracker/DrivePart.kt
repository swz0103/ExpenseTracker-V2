package io.github.swz0103.expensetracker

import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.ClearTokenRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.Scope
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Access tokens for the app's own files on Google Drive, through Google
 * Identity's AuthorizationClient (lib/src/app/android/drive.dart).
 */
class DrivePart(private val activity: FragmentActivity) : ChannelPart {
    private var pendingDrive: MethodChannel.Result? = null

    /** Google's consent screen for the app's own files on Drive. */
    private val askDrive =
        activity.registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { outcome ->
            val result = pendingDrive ?: return@registerForActivityResult
            pendingDrive = null
            try {
                val granted = Identity.getAuthorizationClient(activity)
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
        Identity.getAuthorizationClient(activity).authorize(request)
            .addOnSuccessListener { granted: AuthorizationResult ->
                val pending = granted.pendingIntent
                if (!granted.hasResolution()) {
                    finishDrive(granted.accessToken)
                } else if (!interactive || pending == null) {
                    finishDrive(null)
                } else {
                    pendingDrive?.let { waiting ->
                        launchOr(waiting, { pendingDrive = null }) {
                            askDrive.launch(IntentSenderRequest.Builder(pending.intentSender).build())
                        }
                    }
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

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "driveToken" -> driveToken(call.argument<Boolean>("interactive") == true, result)
            "clearDriveToken" -> {
                val token = call.argument<String>("token")
                if (token == null) {
                    result.error("bad-arguments", "token is required", null)
                } else {
                    Identity.getAuthorizationClient(activity)
                        .clearToken(ClearTokenRequest.builder().setToken(token).build())
                        .addOnCompleteListener { result.success(null) }
                }
            }
            else -> return false
        }
        return true
    }

    private companion object {
        const val DRIVE_SCOPE = "https://www.googleapis.com/auth/drive.file"
    }
}
