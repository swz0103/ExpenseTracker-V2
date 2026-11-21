import 'package:vault/backup_security.dart' show InboxItem;

import '../core/diagnostics/error_log.dart';
import '../core/ledger/ledger.dart';
import '../features/reminders/model/inbox_apply.dart';

/// The inbox of confirmations written while the ledger was locked
/// (「確認入帳」 on notifications): what is in it, and taking one out.
typedef InboxSource = ({
  Future<List<InboxItem>> Function() read,
  Future<void> Function(String name) remove,
});

/// What opening a ledger found to tell the person.
final class SessionStart {
  const SessionStart(this.ledger, {this.inbox, this.booked = 0});

  final Ledger ledger;

  /// What the inbox brought; null when it was empty or could not be read.
  final InboxOutcome? inbox;

  /// Recurring items booked by themselves because their day had come.
  final int booked;
}

/// The steps that change or check a ledger as it opens: load it, apply
/// the inbox, check it is whole, and book what is due. Plain Dart, apart
/// from the screens: they show what [open] returns. A step that fails is
/// logged and the others still run; only loading stops the opening.
final class LedgerSession {
  LedgerSession({required this.load, this.inbox});

  /// Reads the book from where it is kept.
  final Future<Ledger> Function() load;

  /// Opens the inbox; none off Android.
  final Future<InboxSource> Function()? inbox;

  Future<SessionStart> open() async {
    final ledger = await load();
    final inbox = await readInbox(ledger);
    checkIntegrity(ledger);
    final booked = bookDue(ledger);
    return SessionStart(ledger, inbox: inbox, booked: booked);
  }

  /// Applies the inbox, then empties it. Opening the inbox also writes
  /// its public key, which the notifications seal with.
  Future<InboxOutcome?> readInbox(Ledger ledger) async {
    final open = inbox;
    if (open == null) return null;
    try {
      final source = await open();
      final items = await source.read();
      if (items.isEmpty) return null;
      final outcome = applyInbox(
        items,
        recurring: ledger.recurring,
        service: ledger.recurringService,
        commands: ledger.recurringCommands,
      );
      for (final item in items) {
        await source.remove(item.name);
      }
      return outcome;
    } on Object catch (error) {
      ErrorLog.instance.record('收件匣', error);
      return null;
    }
  }

  /// Notes in the diagnostics log each kind of record that names another
  /// the book no longer has, once: the sums still add up, but the book is
  /// not as it was written. A check that cannot finish does not keep the
  /// book from opening.
  void checkIntegrity(Ledger ledger) {
    final List<IntegrityProblem> found;
    try {
      found = ledger.integrityService.problems();
    } on Object catch (error) {
      ErrorLog.instance.record('帳本健檢', error);
      return;
    }
    final kinds = {for (final problem in found) '$problem': problem};
    for (final problem in kinds.values) {
      ErrorLog.instance.record('帳本健檢', problem);
    }
  }

  /// Books the recurring items marked to book themselves whose day has
  /// come; how many. Also when the app comes back, as days pass.
  int bookDue(Ledger ledger) {
    try {
      return ledger.recurringCommands.bookDue();
    } on Object catch (error) {
      ErrorLog.instance.record('定期自動入帳', error);
      return 0;
    }
  }
}
