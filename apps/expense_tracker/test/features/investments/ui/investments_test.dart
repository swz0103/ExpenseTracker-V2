import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/investments/ui/investments.dart'
    show returnsOf;
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';
import '../../../support/seeded_book.dart' show emptyBook;

/// 投資與股息's holdings, grouped: 個股 and ETF (codes starting 00), none
/// sold out counted in either (review 16: the 個股／ETF groups).
void main() {
  test('the returns are kept until the entries, the market or the day '
      'change, not on hiding the amounts (review 32 1.1)', () {
    var today = DateTime.utc(2026, 10, 20);
    final ledger = emptyBook(today: today, clock: () => today);
    Entry buy(String id) => Entry(
      id: id,
      date: DateTime.utc(2026, 10, 1),
      type: EntryType.buy,
      amount: 1000,
      account: 'bank',
      category: investmentCategory,
      holding: '2330',
      shares: 10,
    );
    ledger.entryCommands.add(buy('b1'));
    final kept = returnsOf(ledger);
    ledger.amounts.toggle();
    expect(identical(returnsOf(ledger), kept), isTrue);

    ledger.entryCommands.add(buy('b2'));
    final saved = returnsOf(ledger);
    expect(identical(saved, kept), isFalse);

    ledger.holdingCommands.setMarket(
      holdings: const [],
      moves: const {},
      rates: const {'USD': 32.0},
    );
    final quoted = returnsOf(ledger);
    expect(identical(quoted, saved), isFalse);

    today = DateTime.utc(2026, 10, 21);
    expect(identical(returnsOf(ledger), quoted), isFalse);
    expect(returnsOf(ledger).today, today);
  });

  testWidgets('stocks and ETFs are counted apart, one sold out in neither', (
    tester,
  ) async {
    final ledger = emptyBook();
    var n = 0;
    void trade(EntryType type, String code, int shares) =>
        ledger.entryCommands.add(
          Entry(
            id: 't${n++}',
            date: DateTime.utc(2026, 10, 1 + n),
            type: type,
            amount: shares * 100,
            account: 'bank',
            category: investmentCategory,
            holding: code,
            shares: shares,
          ),
        );
    trade(EntryType.buy, '2330', 10);
    trade(EntryType.buy, '1101', 10);
    trade(EntryType.buy, '0050', 10);
    trade(EntryType.buy, '2317', 10);
    trade(EntryType.sell, '2317', 10);
    await show(tester, 360, 1, height: 1600, book: ledger);
    await go(tester, ['更多', '投資與股息']);
    // 2330 and 1101 held: 個股; 0050: ETF; 2317, all sold, in neither.
    expect(find.text('個股 · 2 檔'), findsOneWidget);
    expect(find.text('ETF · 1 檔'), findsOneWidget);
    expect(find.text('2317'), findsNothing);
  });
}
