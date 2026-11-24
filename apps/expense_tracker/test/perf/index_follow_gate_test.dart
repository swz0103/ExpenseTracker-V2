@Tags(['timing'])
library;

import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/repositories/entry_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/held.dart';

/// Deleting entries, putting them back and moving one to another day
/// cost the lists they touch, not the whole book: the entries' indexes
/// (by month, by account, by id) follow each change rather than being
/// thrown away and worked out again from every entry, which at 100,000
/// entries took 120–150 ms before the next balance could be read.
///
/// Gated as a share of working the same indexes out afresh on a book of
/// 100,000 entries, afresh the least of [gateTries] runs and each change
/// the least of [_stepTries] (tens of microseconds of work: one try a
/// busy host preempts is likely, every try is not), so it holds on any
/// machine. With `BENCH=1` the times are printed as well.
void main() {
  final today = DateTime.utc(2026, 10, 4);
  final bench = Platform.environment['BENCH'] != null;
  const count = 100000;

  List<Entry> entries() {
    final r = Random(1);
    return [
      for (var i = 0; i < count; i++)
        Entry(
          id: 'e$i',
          date: today.subtract(Duration(days: r.nextInt(365 * 3))),
          type: EntryType.expense,
          amount: 30 + r.nextInt(2000),
          // a3 is left untouched by every change below.
          account: 'a${r.nextInt(3)}',
          category: '飲食',
        ),
    ];
  }

  /// What a screen reads right after a change: the month, an entry by
  /// id, the entries of an account the change did not touch.
  void read(EntryReader entries) {
    entries.inMonth(today.year, today.month);
    entries.byId('e1');
    entries.ofAccount('a3');
  }

  test('a delete, its undo and a date move follow the indexes', () async {
    final repository = EntryRepository(entries());
    read(repository);
    for (final account in ['a0', 'a1', 'a2']) {
      repository.ofAccount(account);
    }

    // The indexes worked out afresh from every entry: what each change
    // cost before.
    final afresh = await leastOf(gateTries, () async {
      final watch = Stopwatch()..start();
      read(EntryRepository(repository.all));
      return watch.elapsedMicroseconds;
    });

    /// The least times of a delete, its undo and a date move, each time
    /// on another entry from [first] on, with what a screen reads after.
    Future<Map<String, int>> steps(int first) async {
      var k = 0;
      Future<int> timed(void Function(Entry e) change) =>
          leastOf(_stepTries, () async {
            final e = repository.byId('e${first + 7 * k++}')!;
            final watch = Stopwatch()..start();
            change(e);
            read(repository);
            return watch.elapsedMicroseconds;
          });

      // As the app deletes, and as its undo puts back where it was.
      final undos = <(int, Entry)>[];
      final delete = await timed(
        (e) => undos.addAll(repository.removeEach([e])),
      );
      expect(undos, hasLength(_stepTries));
      var back = 0;
      final undo = await timed((_) {
        final (i, e) = undos[back++];
        repository.insert(i, e);
      });
      expect(repository.length, count);
      final move = await timed((e) {
        final at = repository.indexOf(e);
        repository[at] = Entry(
          id: e.id,
          date: e.date.subtract(const Duration(days: 40)),
          type: e.type,
          amount: e.amount,
          account: e.account,
          category: e.category,
        );
      });
      return {'delete': delete, 'undo': undo, 'move': move};
    }

    // Entries written lately, as are most of those deleted or edited: the
    // indexes alone. One written long ago also moves every later entry
    // along the list, a copy that grows with the book (printed only).
    // Warm up the code paths first, so the steps are not charged for
    // compiling them.
    await steps(count - 3000);
    final recent = await steps(count - 1000);
    if (bench) {
      final early = await steps(1000);
      // ignore: avoid_print
      print('afresh $afresh µs; recent $recent µs; early $early µs');
    }
    for (final MapEntry(key: what, value: us) in recent.entries) {
      expect(
        us / afresh,
        lessThanOrEqualTo(_most),
        reason:
            'a $what took $us µs, working the indexes out afresh $afresh '
            'µs: they were thrown away',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a delete leaves the balance of an untouched account standing', () {
    final ledger = Ledger(
      today: today,
      accounts: [
        for (var i = 0; i < 4; i++)
          Account('a$i', '帳戶$i', AccountKind.bank, 100000),
      ],
      categories: const [],
      entries: entries().take(2000).toList(),
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    final untouched = ledger.entries.versionOf('a3');
    final before = ledger.balanceService.balance('a3');
    final removed = ledger.entryCommands.removeAll(['e10', 'e11', 'e12']);
    expect(removed.map((e) => e.id), ['e10', 'e11', 'e12']);
    expect(ledger.entries.versionOf('a3'), untouched);
    expect(ledger.balanceService.balance('a3'), before);
    expect(ledger.entryCommands.restoreAll(removed), isTrue);
    expect(ledger.entries.versionOf('a3'), untouched);
  });
}

/// The largest share of working the indexes out afresh a change may
/// take: about twice the largest measured (thresholds.md).
const _most = 0.0005;

/// How many tries each change takes the least of: fifteen of tens of
/// microseconds cost well under a millisecond (review 23).
const _stepTries = 15;
