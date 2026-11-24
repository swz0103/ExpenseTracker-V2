import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

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

  testWidgets('the balance above the list is headed with its month '
      '(review 16: N 月結餘)', (tester) async {
    // The demo book's today is 2026-10-04.
    await show(tester, 360, 1, height: 800, book: demoLedger());
    await go(tester, ['紀錄']);
    expect(find.text('10 月結餘'), findsOneWidget);
  });
}
