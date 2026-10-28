import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/investments/model/returns.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing.
final class _Nowhere implements Journal {
  @override
  Future<void> keep(Batch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  final day = DateTime.utc(2026, 10, 20);

  Ledger book(List<Entry> entries) => Ledger(
    today: day,
    accounts: const [Account('bank', '銀行', AccountKind.bank, 1000000)],
    categories: const [],
    entries: entries,
    holdings: const [],
    budgets: const [],
    recurring: const [],
    journal: _Nowhere(),
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
    final rate = returnOf(ledger, code: '0056')!;
    expect(rate, greaterThan(0.05));
    expect(rate, lessThan(0.06));
    expect(returnOf(ledger), closeTo(rate, 1e-9));
    expect(investedSince(ledger), DateTime.utc(2025, 10, 20));
    expect(payingMonths(ledger, '0056'), [1, 7]);
  });

  test("next year's dividends follow this year's, per share held now", () {
    final ledger = book([
      trade('b1', DateTime.utc(2025, 9, 1), EntryType.buy, 36000, shares: 1000),
      trade('d1', DateTime.utc(2026, 1, 15), EntryType.dividend, 1000),
      // Twice the shares since: twice the dividend expected.
      trade('b2', DateTime.utc(2026, 3, 1), EntryType.buy, 36000, shares: 1000),
      trade('d2', DateTime.utc(2026, 7, 15), EntryType.dividend, 2000),
    ]);
    expect(sharesBefore(ledger, '0056', DateTime.utc(2026, 1, 15)), 1000);
    final guesses = expectedDividends(ledger);
    expect(
      [for (final g in guesses) (g.month, g.amount)],
      [(DateTime.utc(2027), 2000), (DateTime.utc(2027, 7), 2000)],
    );
  });
}
