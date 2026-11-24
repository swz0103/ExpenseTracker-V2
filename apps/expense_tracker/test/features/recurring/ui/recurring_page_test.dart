import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/layout_checks.dart';
import '../../../support/places.dart';
import '../../../support/seeded_book.dart' show emptyBook;

/// 定期交易's calendar, with a day due that is not booked yet.
void main() {
  setUpAll(loadFonts);

  testWidgets('到期 under a day due is shown whole, at every text size', (
    tester,
  ) async {
    for (final text in [1.0, 1.5]) {
      final ledger = demoLedger();
      // Due on the 2nd, two days before the demo's today, and not booked.
      ledger.recurringCommands.saveRecurring(
        const Recurring(
          id: 'gym',
          name: '健身房',
          amount: 800,
          day: 2,
          account: 'bank',
          category: '購物休閒',
        ),
      );
      await show(tester, 360, text, book: ledger);
      await go(tester, ['更多', '定期交易']);
      expect(find.text('到期'), findsWidgets);
      expect(cutOff(tester), isEmpty, reason: 'text ${text * 100}%');
    }
  });

  // Today 2026-10-31: gym and rent fall due in October, the insurance
  // only in March.
  Ledger planned() => emptyBook(
    recurring: [
      const Recurring(
        id: 'gym',
        name: '健身房',
        amount: 800,
        day: 2,
        account: 'bank',
        category: '娛樂',
      ),
      const Recurring(
        id: 'rent',
        name: '房租',
        amount: 12000,
        day: 5,
        account: 'bank',
        category: '購物',
      ),
      Recurring(
        id: 'insurance',
        name: '保險',
        amount: 6000,
        day: 10,
        unit: RepeatUnit.year,
        start: DateTime.utc(2026, 3, 10),
        account: 'bank',
        category: '購物',
      ),
      const Recurring(
        id: 'pay',
        name: '薪水',
        amount: 50000,
        day: 5,
        income: true,
        account: 'bank',
        category: '薪水',
      ),
    ],
  );

  /// The recurring item's editor is open on [name].
  Finder editorOn(String name) => find.byWidgetPredicate(
    (w) => w is EditableText && w.controller.text == name,
  );

  testWidgets('管理固定項目 heads each side with 本月合計 (1.5-10)', (tester) async {
    await show(tester, 360, 1, book: planned());
    await go(tester, ['更多', '定期交易', '~管理']);
    // 支出: 800 + 12,000 fall due this month, the insurance (March) not:
    // 12,800. 收入: 50,000.
    expect(find.text('3 項 · 本月合計 12,800'), findsOneWidget);
    expect(find.text('1 項 · 本月合計 50,000'), findsOneWidget);
  });

  testWidgets('a row of 管理固定項目 opens its item to edit (1.5-11)', (
    tester,
  ) async {
    await show(tester, 360, 1, book: planned());
    await go(tester, ['更多', '定期交易', '~管理']);
    expect(editorOn('健身房'), findsNothing);
    await tester.tap(find.text('健身房'));
    await tester.pumpAndSettle();
    expect(editorOn('健身房'), findsOneWidget);
  });

  testWidgets('a row of 訂閱與固定支出 opens its item to edit (1.5-11)', (
    tester,
  ) async {
    await show(tester, 360, 1, book: planned());
    await go(tester, ['更多', '定期交易', '固定支出/年 ›']);
    expect(find.text('訂閱與固定支出'), findsWidgets);
    await tester.tap(find.text('房租'));
    await tester.pumpAndSettle();
    expect(editorOn('房租'), findsOneWidget);
  });
}
