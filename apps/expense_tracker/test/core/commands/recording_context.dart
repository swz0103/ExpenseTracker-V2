import 'package:expense_tracker/src/core/ledger/cache/query_cache.dart';
import 'package:expense_tracker/src/core/ledger/cache/topic.dart';
import 'package:expense_tracker/src/core/ledger/commands/command_context.dart';
import 'package:expense_tracker/src/core/ledger/persistence/write_batch.dart';
import 'package:flutter/foundation.dart';

/// A [CommandContext] that writes down what a command asked of it and,
/// as the ledger does, throws away the answers in [cache] that a change
/// left stale.
final class RecordingContext implements CommandContext {
  RecordingContext(this.today, {this.cache});

  final QueryCache? cache;

  @override
  DateTime today;

  @override
  final problem = ValueNotifier<Object?>(null);

  /// The topics of each change told, in turn.
  final changes = <Set<Topic>>[];

  /// The topics thrown away without telling, in turn.
  final forgotten = <Set<Topic>>[];

  /// How many changes left every sum as it was.
  var signals = 0;

  /// Every batch handed over, in turn.
  final batches = <WriteBatch>[];

  var _ids = 0;

  @override
  String newId() => 'new${_ids++}';

  @override
  void changed(Set<Topic> topics) {
    cache?.forget(topics);
    changes.add(topics);
  }

  @override
  void forget(Set<Topic> topics) {
    cache?.forget(topics);
    forgotten.add(topics);
  }

  @override
  void signal() => signals++;

  @override
  void keep(WriteBatch batch) => batches.add(batch);
}
