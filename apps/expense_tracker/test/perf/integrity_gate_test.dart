@Tags(['timing'])
library;

import 'dart:io';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/held.dart';

/// The integrity check the book runs as it opens, on the screen's
/// isolate, makes nothing for an entry that names nothing missing (review
/// 32 1.4). Before, it made a set of the entry's accounts and a generator
/// for each of them: 20–22 ms warm at 100,000 entries, 65 ms cold.
///
/// On a book of 100,000 entries (transfers and refunds among them, and a
/// few naming what the book lacks) the check is gated as a share of the
/// old one, both warmed up, the least of [gateTries] runs; the problems
/// found must be the same. With `BENCH=1` the times are printed.
void main() {
  final bench = Platform.environment['BENCH'] != null;
  final today = DateTime.utc(2026, 10, 4);

  test('the check at open makes nothing for a sound entry', () async {
    const accounts = [
      Account('bank', '銀行', AccountKind.bank, 0),
      Account('cash', '現金', AccountKind.cash, 0),
    ];
    final entries = [
      for (var i = 0; i < 100000; i++)
        Entry(
          id: 'e$i',
          date: today.subtract(Duration(days: i % 1000)),
          type: switch (i % 10) {
            0 => EntryType.transfer,
            1 => EntryType.income,
            _ => EntryType.expense,
          },
          amount: 100 + i % 900,
          // One in a thousand pays from an account the book lacks.
          account: i % 1000 == 7 ? 'gone' : 'bank',
          to: i % 10 == 0 ? (i % 2000 == 0 ? 'gone too' : 'cash') : null,
          category: i % 10 == 0 ? '' : '飲食',
          refundOf: i % 10 == 1 ? 'e${i - 1 - i % 3}' : null,
        ),
    ];
    final ledger = Ledger(
      today: today,
      accounts: accounts,
      categories: const [],
      entries: entries,
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
    final check = ledger.integrityService;
    final old = _OldCheck(ledger);
    String said(IntegrityProblem p) => switch (p) {
      MissingAccount(:final account) => '$p ${p.id} $account',
      MissingRefundOriginal(:final original) => '$p ${p.id} $original',
    };
    final found = [for (final p in check.problems()) said(p)];
    expect(found, isNotEmpty);
    expect(found, [for (final p in old.problems()) said(p)]);

    Future<int> timed(void Function() run) => leastOf(gateTries, () async {
      final watch = Stopwatch()..start();
      run();
      return watch.elapsedMicroseconds;
    });
    final before = await timed(old.problems);
    final now = await timed(check.problems);
    if (bench) {
      // ignore: avoid_print
      print('old $before µs; now $now µs');
    }
    expect(
      now / before,
      lessThanOrEqualTo(_most),
      reason: 'the check took $now µs, the old one $before µs',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// The largest share of the old check the check may take: about twice the
/// largest measured (thresholds.md).
const _most = 0.6;

/// The check as it was before review 32 1.4: a set and a generator per
/// entry.
final class _OldCheck {
  _OldCheck(this._ledger);

  final Ledger _ledger;

  List<IntegrityProblem> problems() => [
    for (final e in _ledger.entries.all) ..._ofEntry(e),
  ];

  Iterable<IntegrityProblem> _ofEntry(Entry e) sync* {
    for (final account in {e.account, ?e.to}) {
      if (!_ledger.accounts.contains(account)) {
        yield MissingAccount(RecordKind.entry, e.id, account);
      }
    }
    final original = e.refundOf;
    if (original != null && _ledger.entries.byId(original) == null) {
      yield MissingRefundOriginal(RecordKind.entry, e.id, original);
    }
  }
}
