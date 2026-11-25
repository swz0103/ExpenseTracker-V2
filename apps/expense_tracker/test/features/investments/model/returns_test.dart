import 'dart:math';

import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/investments/model/returns.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fuzz.dart';
import '../../../support/whole_book_returns.dart';

/// Keeps nothing.
final class _Nowhere implements LedgerDataSource {
  @override
  Future<void> keep(WriteBatch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  final day = DateTime.utc(2026, 10, 20);

  Ledger book(List<Entry> entries, {DateTime? today}) => Ledger(
    today: today ?? day,
    accounts: const [Account('bank', '銀行', AccountKind.bank, 1000000)],
    categories: [],
    entries: entries,
    holdings: const [],
    budgets: const [],
    recurring: const [],
    dataSource: _Nowhere(),
  );

  Entry trade(
    String id,
    DateTime date,
    EntryType type,
    int amount, {
    int shares = 0,
    int fee = 0,
    int tax = 0,
  }) => Entry(
    id: id,
    date: date,
    type: type,
    amount: amount,
    account: 'bank',
    category: '投資',
    holding: '0056',
    shares: shares,
    fee: fee,
    tax: tax,
  );

  test('XIRR as a spreadsheet gives it', () {
    final start = DateTime.utc(2025);
    expect(
      xirr([(start, -1000), (start.add(const Duration(days: 365)), 1100)]),
      closeTo(0.10, 1e-6),
    );
    // Half a year doubling is a fourfold year.
    expect(
      xirr([(start, -1000), (start.add(const Duration(days: 365 ~/ 2)), 2000)]),
      closeTo(3.0, 0.05),
    );
    expect(xirr([(start, 1000)]), isNull);
    expect(xirr([(start, -1000), (start, -5)]), isNull);
  });

  test('a holding: trades, dividends, and what is held at its close', () {
    final ledger = book([
      trade(
        'b',
        DateTime.utc(2025, 10, 20),
        EntryType.buy,
        36000,
        shares: 1000,
        fee: 20,
      ),
      trade('d1', DateTime.utc(2026, 1, 15), EntryType.dividend, 1000),
      trade('d2', DateTime.utc(2026, 7, 15), EntryType.dividend, 1000),
    ]);
    // Without a close the shares are worth their cost: the dividends are
    // the year's return.
    final rate = returnsOf(ledger).rate(code: '0056')!;
    expect(rate, greaterThan(0.05));
    expect(rate, lessThan(0.06));
    expect(returnsOf(ledger).rate(), closeTo(rate, 1e-9));
    expect(returnsOf(ledger).payingMonths('0056'), [1, 7]);
  });

  test("next year's dividends follow this year's, per share held now", () {
    final ledger = book([
      trade('b1', DateTime.utc(2025, 9, 1), EntryType.buy, 36000, shares: 1000),
      trade('d1', DateTime.utc(2026, 1, 15), EntryType.dividend, 1000),
      // Twice the shares since: twice the dividend expected.
      trade('b2', DateTime.utc(2026, 3, 1), EntryType.buy, 36000, shares: 1000),
      trade('d2', DateTime.utc(2026, 7, 15), EntryType.dividend, 2000),
    ]);
    expect(
      returnsOf(ledger).sharesBefore('0056', DateTime.utc(2026, 1, 15)),
      1000,
    );
    final guesses = returnsOf(ledger).expectedDividends();
    expect(
      [for (final g in guesses) (g.month, g.amount)],
      [(DateTime.utc(2027), 2000), (DateTime.utc(2027, 7), 2000)],
    );
    expect(returnsOf(ledger).nextDividend('0056')?.month, DateTime.utc(2027));
    expect(returnsOf(ledger).nextDividend('2330'), isNull);
  });

  test('R26: on 29 February the last year and two years start after the '
      '28th, not after 1 March', () {
    final ledger = book(today: DateTime.utc(2028, 2, 29), [
      trade('b', DateTime.utc(2025, 9, 1), EntryType.buy, 36000, shares: 1000),
      // A year back from 29 Feb 2028 is 28 Feb 2027: 1 Mar 2027 is
      // inside the last twelve months.
      trade('d1', DateTime.utc(2027, 3, 1), EntryType.dividend, 1000),
      trade('d0', DateTime.utc(2026, 3, 1), EntryType.dividend, 1000),
    ]);
    final guesses = returnsOf(ledger).expectedDividends();
    // d1 a year on: March 2028; d0 is older than a year.
    expect(
      [for (final g in guesses) (g.month, g.amount)],
      [(DateTime.utc(2028, 3), 1000)],
    );
    // Two years back is 28 Feb 2026, so d0 alone still names March.
    final older = book(today: DateTime.utc(2028, 2, 29), [
      trade('b', DateTime.utc(2025, 9, 1), EntryType.buy, 36000, shares: 1000),
      trade('d0', DateTime.utc(2026, 3, 1), EntryType.dividend, 1000),
    ]);
    expect(returnsOf(older).payingMonths('0056'), [3]);
  });

  test('each answer is worked out once and kept', () {
    final returns = returnsOf(
      book([
        trade('b', DateTime.utc(2025, 9, 1), EntryType.buy, 36000, shares: 10),
        trade('d', DateTime.utc(2026, 1, 15), EntryType.dividend, 100),
      ]),
    );
    expect(
      identical(returns.expectedDividends(), returns.expectedDividends()),
      isTrue,
    );
    expect(
      identical(returns.payingMonths('0056'), returns.payingMonths('0056')),
      isTrue,
    );
    expect(returns.rate(), returns.rate());
  });

  // Review 32 1.1: the answers now come from each stock's own trades,
  // kept; they must be those worked out from every entry, as before.
  for (var seed = 0; seed < fuzzSeeds; seed++) {
    test('the same answers as worked out from every entry ($seed)', () {
      final r = Random(seed);
      const codes = ['0056', '2330', '2412'];
      final today = DateTime.utc(2026, 10, 20);
      var serial = 0;
      DateTime someDay() => today.subtract(Duration(days: r.nextInt(800) - 20));
      final entries = <Entry>[];
      for (var i = 0; i < 60; i++) {
        final code = codes[r.nextInt(codes.length)];
        final kind = r.nextInt(8);
        entries.add(
          kind == 0
              ? Entry(
                  id: 'e${serial++}',
                  date: someDay(),
                  type: EntryType.expense,
                  amount: 1 + r.nextInt(500),
                  account: 'bank',
                  category: '飲食',
                )
              : Entry(
                  id: 't${serial++}',
                  date: someDay(),
                  type: switch (kind) {
                    1 || 2 || 3 => EntryType.buy,
                    4 => EntryType.sell,
                    _ => EntryType.dividend,
                  },
                  amount: 100 + r.nextInt(50000),
                  account: 'bank',
                  category: '投資',
                  holding: code,
                  shares: switch (kind) {
                    1 || 2 || 3 => 100 + r.nextInt(2000),
                    4 => 1 + r.nextInt(300),
                    // A stock dividend now and then.
                    _ => r.nextInt(6) == 0 ? 1 + r.nextInt(50) : 0,
                  },
                  fee: r.nextInt(30),
                  tax: kind == 4 ? r.nextInt(30) : 0,
                ),
        );
      }
      final ledger = book(entries, today: today);
      final kept = returnsOf(ledger);
      final before = WholeBookReturns(ledger);
      expect(kept.rate(), before.rate(), reason: 'all');
      expect(kept.expectedDividends(), before.expectedDividends());
      for (final code in [...codes, 'none']) {
        expect(
          kept.rate(code: code),
          before.rate(code: code),
          reason: code,
        );
        expect(kept.nextDividend(code), before.nextDividend(code));
        expect(kept.payingMonths(code), before.payingMonths(code));
        for (var k = 0; k < 5; k++) {
          final day = someDay();
          expect(
            kept.sharesBefore(code, day),
            before.sharesBefore(code, day),
            reason: '$code $day',
          );
        }
      }
    });
  }
}

/// [ledger]'s returns, from the parts the model reads.
Returns returnsOf(Ledger ledger) => Returns(
  entries: ledger.entries,
  holdings: ledger.holdings,
  trades: ledger.entryQueryService,
  today: ledger.today,
);
