import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/features/entries/forms/composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';
import '../../../support/seeded_book.dart' show emptyBook;

/// 收支紀錄's search: what is typed is looked for after a pause in typing,
/// the balance above says what is searched for, and the search's ✕ takes
/// it away. (The time a search takes on a large book is the timing gate's,
/// test/perf/records_page_gate_test.dart.)
void main() {
  testWidgets('a search waits for a pause in typing, and its ✕ ends it', (
    tester,
  ) async {
    final ledger = demoLedger();
    await show(tester, 360, 1, height: 800, book: ledger);
    await go(tester, ['紀錄']);
    final field = find.byType(TextField).first;
    final clear = find.descendant(of: field, matching: find.byType(IconButton));
    expect(clear, findsNothing, reason: 'nothing typed, nothing to clear');

    await tester.enterText(field, '午');
    // Not yet: the search waits 250 ms after the last letter.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('搜尋「午」'), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('搜尋「午」'), findsOneWidget);

    expect(clear, findsOneWidget);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(find.text('搜尋「午」'), findsNothing);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
  });

  testWidgets('D85: a book with nothing written says so, with 記一筆', (
    tester,
  ) async {
    await show(tester, 360, 1, height: 800, book: emptyBook());
    await go(tester, ['紀錄']);
    expect(find.text('還沒有紀錄'), findsOneWidget);
    expect(find.text('沒有符合篩選的紀錄'), findsNothing);
    await tester.tap(find.byKey(Keys.emptyAction('entries')));
    await tester.pumpAndSettle();
    expect(find.byType(Composer), findsOneWidget);
  });

  testWidgets('D85: a search that finds nothing says so, and 清除篩選 '
      'brings the list back', (tester) async {
    await show(tester, 360, 1, height: 800, book: demoLedger());
    await go(tester, ['紀錄']);
    await tester.enterText(find.byType(TextField).first, '沒有這種東西');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('沒有符合篩選的紀錄'), findsOneWidget);
    expect(find.text('還沒有紀錄'), findsNothing);
    await tester.tap(find.byKey(Keys.emptyAction('entries')));
    await tester.pumpAndSettle();
    expect(find.text('沒有符合篩選的紀錄'), findsNothing);
    expect(find.textContaining('搜尋「'), findsNothing);
  });
}
