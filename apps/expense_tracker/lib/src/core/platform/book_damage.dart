import 'package:storage/storage.dart'
    show StorageProblem, StorageUnavailable, isNoSpace;
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import '../diagnostics/error_log.dart';
import '../diagnostics/error_steps.dart';
import 'startup_state.dart';

/// What the `Startup` does for [BookDamage]: the states it shows as the
/// damage is handled, and the book it closes.
typedef DamageSteps = ({
  // Closes the open book, its keys and what was held for it given up;
  // the keys it was open with, null when none was open.
  UnlockedKeyring? Function() close,

  // Notes the error and shows Damaged.
  void Function(Object error) damaged,

  // Back to the lock screen; noSpace when the phone was found full.
  void Function({bool noSpace}) locked,

  // The book opened again.
  void Function(OpenVault open) ready,
});

/// The ledger's database found damaged (D94, D102): one handling at a
/// time, the book made again from its records once a launch where they
/// still read whole, set aside as it is otherwise.
final class BookDamage {
  BookDamage(this._vault, this._steps);

  final LedgerVault _vault;
  final DamageSteps _steps;

  /// Opens the ledger with [open]; a database found damaged as it opens
  /// ([StorageProblem.damaged]) turns this into [Damaged] before it is
  /// thrown on: the vault has set it aside already.
  Future<OpenVault> watch(Future<OpenVault> Function() open) async {
    try {
      return await open();
    } on StorageUnavailable catch (error) {
      if (error.problem == StorageProblem.damaged) _steps.damaged(error);
      rethrow;
    }
  }

  /// The damage being handled now ([bookDamaged], [journalDamaged]):
  /// one at a time, a report while it runs waits for it rather than
  /// closing and making the book again a second time.
  Future<void>? _damage;

  /// Runs [handle] as the one damage handling, or waits for the one
  /// running.
  Future<void> _oneDamage(Future<void> Function() handle) =>
      _damage ??= handle().whenComplete(() => _damage = null);

  /// The open ledger's database was found damaged as the book was read
  /// (D94): it is closed. Where its records can still be read whole, the
  /// damage was in the journal's tables, derived from them: the database
  /// is made again from the records and opens again at once, the journal
  /// posted afresh (D102); once a launch, so a book found damaged again
  /// is not made again and again (review 25). Else the app shows
  /// [Damaged], then the file is set aside as it is, never written over;
  /// a set-aside that fails is thrown, the app already showing
  /// [Damaged]. A report while one is handled waits for that one.
  Future<void> bookDamaged(Object error) => _oneDamage(() => _handle(error));

  /// Whether a book was made again from its records this launch
  /// ([_salvage]): a second damage found is set aside, not made again.
  var _salvageSpent = false;

  Future<void> _handle(Object error) async {
    final keys = _steps.close();
    if (keys != null && !_salvageSpent && await _salvage(keys, error)) {
      return;
    }
    // Shown first: a set-aside that fails leaves no open book behind a
    // state that says there is one, so the next fault is not handled
    // again (review 25).
    _steps.damaged(error);
    await _vault.setAsideDamaged();
  }

  /// The journal's tables of the open ledger were found damaged (D102):
  /// noted first, so the next opening makes the database again should
  /// this one not finish, then as [bookDamaged]. Whether the report was
  /// acted on: false when no book is open ([bookOpen] false: locked
  /// meanwhile), so it is to be told again once one is.
  Future<bool> journalDamaged(Object error, {required bool bookOpen}) async {
    if (_damage == null && !bookOpen) return false;
    await _oneDamage(() async {
      try {
        await _vault.noteJournalDamaged();
      } on Object catch (noted) {
        ErrorLog.instance.record(ErrorSteps.journalDamagedNote, noted);
      }
      await _handle(error);
    });
    return true;
  }

  /// Makes the ledger, closed, again from its records with [keys]
  /// ([LedgerVault.salvage]) and opens it. Whether it was handled here:
  /// false when its records cannot be read whole, or putting the copy in
  /// place failed, which leaves it to be set aside. Once made again, the
  /// book is never set aside for an opening that fails (review 25): one
  /// that finds it damaged has set it aside already and shows [Damaged];
  /// any other failure goes back to the lock screen, where opening is
  /// tried again as any opening is. Making it again that fails before
  /// the copy is put in place (a disk full as it is written) leaves the
  /// file as it was (D113): nothing is set aside, the lock screen comes
  /// back, and the next opening, or the next damage found, makes it
  /// again; only a book made again counts as this launch's one. After
  /// [LedgerVault.salvageTries] such failures in one launch it is set
  /// aside as any damaged book is (review 28).
  Future<bool> _salvage(UnlockedKeyring keys, Object error) async {
    try {
      switch (await _vault.salvage(keys)) {
        case Salvaged(:final noteKept):
          if (noteKept case (final failed, final stack)) {
            ErrorLog.instance.record(
              ErrorSteps.journalDamagedNote,
              failed,
              stack,
            );
          }
        case SalvageUnreadable():
          return false;
        case SalvageNotMade(error: final failed, :final stack, :final gaveUp):
          ErrorLog.instance.record(ErrorSteps.salvageNotMade, failed, stack);
          // Failed too often this launch: set aside as damaged instead.
          // A disk full never counts towards it (review 29).
          if (gaveUp) return false;
          _steps.locked(noSpace: isNoSpace(failed));
          return true;
      }
    } on Object catch (failed) {
      // Failed as the copy was put in place: the book was made again.
      _salvageSpent = true;
      ErrorLog.instance.record(ErrorSteps.bookDamaged, failed);
      return false;
    }
    _salvageSpent = true;
    ErrorLog.instance.record(ErrorSteps.journalRebuilt, error);
    try {
      _steps.ready(await _vault.reopen(keys));
    } on Object catch (failed) {
      if (failed case StorageUnavailable(problem: StorageProblem.damaged)) {
        _steps.damaged(failed);
      } else {
        ErrorLog.instance.record(ErrorSteps.rebuiltNotOpened, failed);
        _steps.locked();
      }
    }
    return true;
  }

  /// What [read], the open book being read, gives; a page of it found
  /// damaged ([StorageProblem.damaged]) is handled first ([bookDamaged])
  /// and thrown on as it was: a handling that fails is noted, never put
  /// in its place (review 25).
  Future<T> reading<T>(Future<T> read) async {
    try {
      return await read;
    } on StorageUnavailable catch (error) {
      if (error.problem == StorageProblem.damaged) {
        try {
          await bookDamaged(error);
        } on Object catch (failed, stack) {
          ErrorLog.instance.record(ErrorSteps.bookDamaged, failed, stack);
        }
      }
      rethrow;
    }
  }
}
