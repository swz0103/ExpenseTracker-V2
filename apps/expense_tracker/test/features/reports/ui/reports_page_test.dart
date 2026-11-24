import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';
import '../../../support/seeded_book.dart' show emptyBook;

/// 財務報表's percents, each rounded to a whole percent (review 16:
/// percent call sites): the biggest category's share of spending, and
/// what was kept as a share of income in the year's summary.
void main() {
  // Today 2026-10-31, the report opens on the year 2026: 50,000 earned,
  // 3,000 on 飲食 and 1,000 on 交通 spent.
  Ledger book() {
    final ledger = emptyBook();
    for (final (id, type, amount, category) in [
      ('pay', EntryType.income, 50000, '薪水'),
      ('food', EntryType.expense, 3000, '飲食'),
      ('bus', EntryType.expense, 1000, '交通'),
    ]) {
      ledger.entryCommands.add(
        Entry(
          id: id,
          date: DateTime.utc(2026, 10, 3),
          type: type,
          amount: amount,
          account: 'bank',
          category: category,
        ),
      );
    }
    return ledger;
  }

  testWidgets('分類 heads with the biggest category and its share', (
    tester,
  ) async {
    await show(tester, 360, 1, height: 1200, book: book());
    await go(tester, ['更多', '財務報表', '分類']);
    // 3,000 of 4,000 spent = 75%.
    expect(find.text('最大分類 飲食 75%'), findsOneWidget);
  });

  testWidgets('the year\'s 存下 is said as a share of income', (tester) async {
    await show(tester, 360, 1, height: 1200, book: book());
    await go(tester, ['更多', '財務報表', '習慣']);
    // 50,000 − 4,000 = 46,000 kept; 46,000 / 50,000 = 92%.
    expect(find.textContaining('（收入的 92%）'), findsOneWidget);
  });
}
