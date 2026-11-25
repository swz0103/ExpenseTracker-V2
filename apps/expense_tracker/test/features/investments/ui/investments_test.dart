import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';
import '../../../support/seeded_book.dart' show emptyBook;

/// 投資與股息's holdings, grouped: 個股 and ETF (codes starting 00), none
/// sold out counted in either (review 16: the 個股／ETF groups).
void main() {
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
