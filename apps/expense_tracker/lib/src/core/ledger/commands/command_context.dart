import 'package:flutter/foundation.dart' show ValueNotifier;

import '../cache/topic.dart';
import '../persistence/write_batch.dart';
import 'command_exceptions.dart';

/// What every command needs of the ledger it changes (Core J2EE Patterns:
/// Context Object): the day, how to tell the screens what changed, and
/// where to hand the records to keep.
abstract interface class CommandContext {
  /// Today, as a UTC midnight.
  DateTime get today;

  /// The last change refused, for the screens to report.
  ValueNotifier<LedgerProblem?> get problem;

  /// Tells the screens of a change refused, through [problem], when no
  /// one asked for it who could be told otherwise: an undo, the trash.
  void report(LedgerProblem refused);

  /// A new id for a record.
  String newId();

  /// Throws away what rests on [topics] and tells the screens.
  void changed(Set<Topic> topics);

  /// Throws away what rests on [topics] without telling the screens, for
  /// a change still under way.
  void forget(Set<Topic> topics);

  /// Tells the screens of a change that leaves every sum as it was.
  void signal();

  /// Hands [batch] to the data source, after the changes before it.
  void keep(WriteBatch batch);
}
