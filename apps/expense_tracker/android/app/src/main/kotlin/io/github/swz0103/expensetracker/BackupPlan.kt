package io.github.swz0103.expensetracker

/**
 * How the background job (BackupWorker.kt) decides; kept apart from
 * Android so it is tested on its own. The rules themselves (how many
 * stay, how often, the names) are the app's (backup_rules.dart): the app
 * hands them over with each backup, as [Handed], and this side keeps none.
 */
internal object BackupPlan {
    /**
     * The rules handed over with a backup (`plan` in the outbox's
     * ready.json, `BackupRules.handover`): how many backups stay, the
     * phone folder's two rhythms and Drive's (milliseconds), the name this
     * backup takes in the phone's folder and how this ledger's names start
     * and end there, and the Drive folder's name.
     */
    data class Handed(
        val keep: Int,
        val daily: Long,
        val weekly: Long,
        val drive: Long,
        val phoneName: String,
        val phonePrefix: String,
        val suffix: String,
        val driveFolder: String,
    ) {
        /** The phone folder's rhythm the person chose. */
        fun phoneEvery(daily: Boolean): Long = if (daily) this.daily else weekly
    }

    /**
     * Whether a backup of [revision] is due at [now]: none was made yet,
     * or the last one, at [last] of [lastRevision], is at least [every]
     * old and the ledger changed since.
     */
    fun due(now: Long, last: Long?, lastRevision: Int?, revision: Int, every: Long): Boolean =
        last == null || (now - last >= every && lastRevision != revision)

    /**
     * Delivers to [places] in turn, writing down what was noted ([noted])
     * with [write] after each and however the run ends: a run stopped (or
     * failing) at a later place still keeps that an earlier one received
     * the backup, so it is not copied there again (review 26). It is
     * written only when it changed since the last write, [written] being
     * what is there already (null for nothing): a run that delivers
     * nothing writes nothing (review 28). A failure to write down after a
     * place that already failed, or was stopped, never takes that one's
     * place: it is added to it as suppressed, so a stop still ends the
     * run as a stop (review 28).
     */
    fun inTurn(
        places: List<() -> Unit>,
        noted: () -> String,
        written: String?,
        write: (String) -> Unit,
    ) {
        var last = written
        fun keep() {
            val now = noted()
            if (now == last) return
            write(now)
            last = now
        }
        var failure: Throwable? = null
        try {
            for (place in places) {
                place()
                keep()
            }
        } catch (e: Throwable) {
            failure = e
            throw e
        } finally {
            try {
                keep()
            } catch (e: Exception) {
                val first = failure ?: throw e
                if (first !== e) first.addSuppressed(e)
            }
        }
    }

    /** The phone's folder no longer lets the app write, or no longer opens: one to choose again. */
    class FolderDenied : IllegalStateException(FOLDER_DENIED)

    /** The code of [FolderDenied]; the app has the words for it (BackgroundProblem). */
    const val FOLDER_DENIED = "FolderDenied"

    /** The code of a failure with no name of its own to give. */
    const val UNKNOWN = "Unknown"

    /**
     * What the app's error log is told of a failure, as a code in plain
     * ASCII: [FOLDER_DENIED] for the folder refusing, Drive's status when
     * Drive refused, and otherwise the failure's type alone. Never its
     * message, which can quote a server or name a file or an account
     * (review 33); the app turns none of it into words of its own.
     */
    fun problemOf(cause: Throwable): String = when {
        cause is FolderDenied -> FOLDER_DENIED
        cause is DriveUploader.Refused && cause.status > 0 -> "Refused HTTP ${cause.status}"
        else -> cause.javaClass.simpleName
            .filter { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' }
            .ifEmpty { UNKNOWN }
    }

    /**
     * Of the names in the phone's folder, this ledger's ([Handed.phonePrefix]
     * and [Handed.suffix]) beyond the newest [Handed.keep]; other files,
     * and other ledgers' backups, are never among them.
     */
    fun beyondKept(names: List<String>, plan: Handed): List<String> =
        names.filter { it.startsWith(plan.phonePrefix) && it.endsWith(plan.suffix) }
            .sortedDescending()
            .drop(plan.keep)
}
