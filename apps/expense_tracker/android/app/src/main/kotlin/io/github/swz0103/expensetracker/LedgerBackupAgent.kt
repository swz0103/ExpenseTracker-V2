package io.github.swz0103.expensetracker

import android.app.backup.BackupAgent
import android.app.backup.BackupDataInput
import android.app.backup.BackupDataOutput
import android.app.backup.FullBackupDataOutput
import android.os.Build
import android.os.ParcelFileDescriptor
import java.io.File

/**
 * Android's own backup, as before: the rules in res/xml take only
 * files/cloud/ (the encrypted ledger without its photos). It also writes
 * down when Android took that copy for the person's Google account, in
 * files/google-backup-taken (not itself backed up), so 設定 › 備份與還原
 * shows when the backup really happened rather than when the app wrote
 * its copy. A copy moved to a new phone by cable or Wi-Fi does not count.
 */
class LedgerBackupAgent : BackupAgent() {
    override fun onFullBackup(data: FullBackupDataOutput) {
        super.onFullBackup(data)
        if (!forAccount(Build.VERSION.SDK_INT, data.transportFlags)) return
        try {
            File(filesDir, TAKEN).writeText(System.currentTimeMillis().toString())
        } catch (_: Exception) {
            // Only the time shown in settings is lost; the backup stands.
        }
    }

    // Only the full backup above is used (fullBackupOnly in the manifest).
    override fun onBackup(
        oldState: ParcelFileDescriptor?,
        data: BackupDataOutput?,
        newState: ParcelFileDescriptor?,
    ) {}

    override fun onRestore(
        data: BackupDataInput?,
        appVersionCode: Int,
        newState: ParcelFileDescriptor?,
    ) {}

    companion object {
        const val TAKEN = "google-backup-taken"

        /**
         * The one folder Android's backup takes, as res/xml names it for
         * every Android version: the app writes its copy there as
         * `記帳本.etbk` (LedgerFolder.cloudCopy), only ever by a rename (F65).
         */
        const val FOLDER = "cloud/"

        /**
         * Whether a backup with [transportFlags], on Android [sdk], goes to
         * the person's Google account, not to a new phone by cable or
         * Wi-Fi (told apart since Android 9).
         */
        fun forAccount(sdk: Int, transportFlags: Int): Boolean =
            sdk < Build.VERSION_CODES.P || (transportFlags and FLAG_DEVICE_TO_DEVICE_TRANSFER) == 0
    }
}
