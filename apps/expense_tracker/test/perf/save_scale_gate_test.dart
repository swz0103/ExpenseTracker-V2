import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Saving one entry costs the same however big the book is: validating it
/// against the write rules, keeping it, and the entries' indexes that a
/// screen reads right after (a month's entries, an entry by id), which a
/// save must keep up to date one entry at a time rather than throw away.
/// Measured as a ratio of a 100,000-entry book to a 3,600-entry one, so it
/// holds on any machine; the time a phone takes is the emulator bench's
/// (integration_test/bench_test.dart, `save`).
void main() {
  final today = DateTime.utc(2026, 10, 4);

  Ledger book(int count) {
    final r = Random(1);
    return Ledger(
      today: today,
      accounts: [
        for (var i = 0; i < 3; i++)
          Account('a$i', '帳戶$i', AccountKind.bank, 100000),
      ],
      categories: const [],
      entries: [
        for (var i = 0; i < count; i++)
          Entry(
            id: 'e$i',
            date: today.subtract(Duration(days: r.nextInt(365 * 5))),
            type: r.nextInt(8) == 0 ? EntryType.income : EntryType.expense,
            amount: 30 + r.nextInt(2000),
            account: 'a${r.nextInt(3)}',
            category: '飲食',
          ),
      ],
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );
  }

  /// The median time, in microseconds, of validating, saving and reading
  /// back one entry on a book of [count].
  int saveOne(int count) {
    final ledger = book(count);
    // What a screen has read before the save.
    ledger.entries.inMonth(today.year, today.month);
    ledger.entries.byId('e0');
    final times = <int>[];
    for (var k = 0; k < 15; k++) {
      final entry = Entry(
        id: 'new$k',
        date: today,
        type: EntryType.expense,
        amount: 120,
        account: 'a0',
        category: '飲食',
      );
      final watch = Stopwatch()..start();
      expect(ledger.entryValidator.validate(entry), isNull);
      ledger.entryCommands.add(entry);
      expect(ledger.entries.inMonth(today.year, today.month), contains(entry));
      expect(ledger.entries.byId(entry.id), same(entry));
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    return times[times.length ~/ 2];
  }

  test('saving one entry does not grow with the book', () {
    // Warm up the code paths first, so the small book is not charged for
    // compiling them.
    saveOne(3600);
    final small = saveOne(3600);
    final large = saveOne(100000);
    // A floor of 50 µs keeps timer noise on a tiny figure from deciding.
    final ratio = large / max(small, 50);
    expect(
      ratio,
      lessThanOrEqualTo(3),
      reason:
          'one save took $small µs on 3,600 entries and $large µs on '
          '100,000: something scans the book on every save',
    );
  });
}
