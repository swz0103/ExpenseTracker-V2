import 'package:expense_tracker/src/core/ledger/cache/topic.dart';
import 'package:expense_tracker/src/core/ledger/commands/command_exceptions.dart';
import 'package:expense_tracker/src/core/ledger/commands/held_notices.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_context.dart';

/// R20: what a command tells, at once or held back to the end of a
/// change still under way.
void main() {
  test('outside a quiet change everything is told at once', () {
    final context = RecordingContext(DateTime.utc(2026, 10, 1));
    final told = HeldNotices(context);
    told.changed(const {Topic.entries});
    told.signal();
    final refused = StayedInTrash(1);
    told.report(refused);
    expect(context.changes, [
      {Topic.entries},
    ]);
    expect(context.signals, 1);
    expect(context.problem.value, same(refused));
    expect(context.forgotten, isEmpty);
  });

  test('a quiet change forgets as it goes and tells its first refusal, '
      'then every topic, once at the end', () {
    final context = RecordingContext(DateTime.utc(2026, 10, 1));
    final told = HeldNotices(context);
    final first = StayedInTrash(1);
    final result = told.quietly(() {
      told.changed(const {Topic.entries});
      // Within another, part of that one.
      told.quietly(() => told.changed(const {Topic.accounts}));
      told.report(first);
      told.report(StayedInTrash(2));
      told.signal();
      expect(context.changes, isEmpty);
      expect(context.problem.value, isNull);
      return 7;
    });
    expect(result, 7);
    expect(context.forgotten, [
      {Topic.entries},
      {Topic.accounts},
    ]);
    expect(context.problem.value, same(first));
    expect(context.changes, [
      {Topic.entries, Topic.accounts},
    ]);
    // Told by the change of the topics.
    expect(context.signals, 0);
  });

  test('a quiet change of no topic that signalled signals once', () {
    final context = RecordingContext(DateTime.utc(2026, 10, 1));
    final told = HeldNotices(context);
    told.quietly(() {
      told.signal();
      told.signal();
    });
    expect(context.signals, 1);
    expect(context.changes, isEmpty);
  });

  test('what was held is told even when the change throws', () {
    final context = RecordingContext(DateTime.utc(2026, 10, 1));
    final told = HeldNotices(context);
    expect(
      () => told.quietly<void>(() {
        told.changed(const {Topic.recurring});
        throw StateError('x');
      }),
      throwsStateError,
    );
    expect(context.changes, [
      {Topic.recurring},
    ]);
    // And the next change is told at once again.
    told.changed(const {Topic.budgets});
    expect(context.changes.last, {Topic.budgets});
  });
}
