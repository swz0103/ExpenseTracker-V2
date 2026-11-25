// Work package 1.1: one amount type for parsing, showing and reading out.
// Fixed in 1.1; kept as regression tests of the findings.
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/widgets/entry_tile.dart';
import 'package:expense_tracker/src/features/accounts/model/account_form.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_page.dart'
    show importBookOf;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../baseline/baseline_ledger.dart';
import '../support/places.dart';

void main() {
  testWidgets(
    'F107: a spending row is read out as spending, not by its minus sign',
    (tester) async {
      final handle = tester.ensureSemantics();
      final ledger = ledgerOf(
        today: day(2026, 10, 4),
        accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
        categories: [Category('飲食', 'food', 0xFF5C9A83)],
      );
      final spending = entryOf(
        'e',
        day(2026, 10, 4),
        EntryType.expense,
        1844,
        'bank',
        category: '飲食',
        merchant: '好市多',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: EntryTile(ledger: ledger, entry: spending, onTap: () {}),
          ),
        ),
      );
      // A screen reader says it is spending, and how much.
      expect(find.bySemanticsLabel(RegExp('支出.*1,844')), findsWidgets);
      handle.dispose();
    },
  );

  test('IMP-04: an amount written as .5 does not abort the whole import', () {
    final ledger = ledgerOf(today: day(2026, 10, 20));
    Import? found;
    expect(
      () => found = importCsv(
        importBookOf(ledger),
        '日期,類型,金額\n2026-10-01,支出,.5\n2026-10-02,支出,40\n',
        fallback: 'bank',
      ),
      returnsNormally,
    );
    // The good line is read, whatever becomes of the odd one.
    expect(found!.entries.map((e) => e.amount), contains(40));
  });

  testWidgets(
    'F78: a month spent 0.3% over its total budget says 超支, not 100%',
    (tester) async {
      final ledger = ledgerOf(
        today: day(2026, 11, 22),
        accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
        categories: [Category('飲食', 'food', 0xFF5C9A83)],
        budgets: const [Budget(allSpending, 50000)],
        entries: [
          // 50,174 spent of 50,000 is 100.35%: over.
          entryOf(
            'e',
            day(2026, 11, 3),
            EntryType.expense,
            50174,
            'bank',
            category: '飲食',
          ),
        ],
      );
      await show(tester, 420, 1, book: ledger);
      await go(tester, ['更多', '預算管理', '11 月，選月份']);
      final texts = [
        for (final e in find.byType(Text).evaluate()) (e.widget as Text).data,
      ];
      expect(texts[texts.lastIndexOf('11 月') + 1], '超支');
    },
  );

  test(
    'ACC-05: a credit limit typed with a thousands comma is read as typed',
    () {
      final ledger = ledgerOf(today: day(2026, 10, 4));
      final form = AccountForm(ledger)
        ..kind = AccountKind.card
        ..name = '卡'
        ..limit = '80,000';
      expect(form.build().limit, 80000);
    },
  );
}
