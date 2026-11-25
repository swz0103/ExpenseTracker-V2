import 'package:ledger_entries/rules.dart' show RecordIssue;

import '../../diagnostics/app_fault.dart';

/// What went wrong with a change of the ledger, for the screens to tell:
/// a change refused, or one the data source could not keep. Every case
/// the ledger can report is one of these, so a screen that tells them all
/// apart can be checked by the compiler.
sealed class LedgerProblem implements AppFault {
  const LedgerProblem();
}

/// A record the ledger's write rules refuse (package ledger_entries):
/// [issues] say why, the errors of each record refused in turn. Every
/// command that writes throws it before it changes anything, whoever
/// calls it: a form, an import, a booking; undo and the trash, with no
/// form to answer, tell it through the ledger's problem instead.
final class RecordRefused extends LedgerProblem {
  RecordRefused(Iterable<RecordIssue> issues)
    : issues = List.unmodifiable(issues) {
    if (this.issues.isEmpty) throw ArgumentError.value(issues, 'issues');
  }

  final List<RecordIssue> issues;

  /// The reason to tell first.
  RecordIssue get first => issues.first;

  @override
  String toString() => 'RecordRefused(${issues.join(', ')})';
}

/// A category was not added or renamed: its name is empty, taken, or one
/// the ledger keeps for itself.
final class NameTaken extends LedgerProblem {
  const NameTaken();

  @override
  String toString() => 'NameTaken';
}

/// A change made on screen could not be kept by the data source; the book
/// is read back as it was kept.
final class KeepFailed extends LedgerProblem implements CarriedFault {
  const KeepFailed(this.cause);

  /// What the data source threw.
  final Object cause;

  @override
  String toString() => 'KeepFailed($cause)';
}

/// An undo put back only part of what was deleted, or none of it: [count]
/// entries stay in the trash, because something stands in their way that
/// the person decides on there, one by one (D78): an account closed since,
/// or a refund's purchase not in the book.
final class StayedInTrash extends LedgerProblem {
  StayedInTrash(this.count);

  /// How many entries stayed.
  final int count;

  @override
  String toString() => 'StayedInTrash($count)';
}

/// After a change could not be kept, the book could not be read back
/// either; what the screens show may differ from what is kept.
final class ReloadFailed extends LedgerProblem implements CarriedFault {
  const ReloadFailed(this.cause);

  /// What the data source threw.
  final Object cause;

  @override
  String toString() => 'ReloadFailed($cause)';
}
