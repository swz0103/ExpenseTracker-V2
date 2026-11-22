/// Checks the year of months on 預算管理: each month says how much of its
/// budget was used, months to come cannot be picked, a year is stepped
/// through by its arrows as far as the book goes, and a month picked is
/// the one shown.
/// Also 幫哪個設額度: a category picked there is given the allowance typed.
library;

import 'dart:ui' show Tristate;

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/formatting/words.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

void main() {
  late Ledger ledger;
  // The demo book begins in January of last year.
  setUp(() => ledger = demoLedger());

  /// What each month of 2026 in the demo book says under its name: the
  /// share of the 32,000 budget spent, rounded half away from zero, or
  /// 超支 when more than 32,000 was spent; months to come say nothing.
  const used2026 = {
    1: '超支', // 36,409 > 32,000
    2: '超支', // 43,694 > 32,000
    3: '超支', // 35,319 > 32,000
    4: '78%', // 24,849 / 32,000 = 77.65%
    5: '79%', // 25,294 / 32,000 = 79.04%
    6: '80%', // 25,739 / 32,000 = 80.43%
    7: '超支', // 62,184 > 32,000
    8: '83%', // 26,629 / 32,000 = 83.22%
    9: '85%', // 27,074 / 32,000 = 84.61%
    10: '55%', // 17,519 / 32,000 = 54.75%
    11: ' ',
    12: ' ',
  };

  testWidgets('each month of this year says how much of its budget was used', (
    tester,
  ) async {
    await show(tester, 420, 1, book: ledger);
    await go(tester, ['更多', '預算管理', '10 月，選月份']);
    expect(find.text('2026'), findsOneWidget);
    final texts = [
      for (final e in find.byType(Text).evaluate()) (e.widget as Text).data,
    ];
    for (var m = 1; m <= 12; m++) {
      final at = texts.lastIndexOf('$m 月');
      expect(texts[at + 1], used2026[m], reason: '$m 月');
    }
    // The months still to come cannot be picked.
    final semantics = tester.ensureSemantics();
    final december = tester.getSemantics(find.bySemanticsLabel('12 月'));
    expect(
      december.getSemanticsData().flagsCollection.isEnabled,
      Tristate.isFalse,
    );
    semantics.dispose();
  });

  testWidgets('a month of last year is reached by its arrow and shown', (
    tester,
  ) async {
    await show(tester, 420, 1, book: ledger);
    await go(tester, ['更多', '預算管理', '10 月，選月份', '~前一年']);
    expect(find.text('2025'), findsOneWidget);
    final texts = [
      for (final e in find.byType(Text).evaluate()) (e.widget as Text).data,
    ];
    // March 2025: 35,664 spent of 32,000.
    expect(texts[texts.lastIndexOf('3 月') + 1], '超支');
    // No year before the book's first.
    await go(tester, ['~前一年']);
    expect(find.text('2025'), findsOneWidget);
    await go(tester, ['~下一年']);
    expect(find.text('2026'), findsOneWidget);
    await go(tester, ['~前一年', '11 月']);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('11 月，選月份'), findsOneWidget);
    expect(find.text('回到本月'), findsOneWidget);
    semantics.dispose();
    await go(tester, ['回到本月']);
    expect(find.text('回到本月'), findsNothing);
    expect(find.text('10 月'), findsOneWidget);
  });

  testWidgets('an allowance is set for a category that had none', (
    tester,
  ) async {
    final free = ledger.categories
        .forEntries(income: false)
        .firstWhere((c) => ledger.budgets.forCategory(c.name).limit == 0)
        .name;
    await show(tester, 420, 1, book: ledger);
    await go(tester, ['更多', '預算管理', '為分類或標籤設定額度']);
    expect(find.text('幫哪個設額度'), findsOneWidget);
    await go(tester, [free, '每月額度 0']);
    for (final key in ['3', '0', '0', '0', Words.done]) {
      await tester.tap(find.byKey(Keys.calc(key)));
      await tester.pumpAndSettle();
    }
    await go(tester, ['儲存']);
    expect(ledger.budgets.forCategory(free).limit, 3000);
  });
}
