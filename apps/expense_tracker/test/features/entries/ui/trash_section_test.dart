import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/entries/ui/trash_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

void main() {
  Future<void> show(WidgetTester tester, Ledger ledger) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: ledger,
            builder: (context, _) =>
                ListView(children: [TrashSection(ledger: ledger)]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Entry anExpense(Ledger ledger) => ledger.entries.all.firstWhere(
    (e) => e.type == EntryType.expense && e.recurring == null,
  );

  testWidgets('an empty trash says so', (tester) async {
    final ledger = demoLedger();
    expect(ledger.trash.all, isEmpty);
    await show(tester, ledger);
    expect(find.text('沒有刪除的紀錄'), findsOneWidget);
  });

  testWidgets('a deleted entry shows how long it is kept, and 放回 brings '
      'it back', (tester) async {
    final ledger = demoLedger();
    final entry = anExpense(ledger);
    final count = ledger.entries.length;
    ledger.entryCommands.remove(entry.id);
    await show(tester, ledger);

    expect(find.text('1 筆'), findsOneWidget);
    expect(find.text('保留 30 天'), findsOneWidget);
    expect(find.textContaining('還剩 30 天'), findsOneWidget);
    expect(find.textContaining(entry.title), findsWidgets);

    await go(tester, ['放回']);
    expect(ledger.trash.all, isEmpty);
    expect(ledger.entries.length, count);
    expect(find.text('已放回「${entry.title}」'), findsOneWidget);
    expect(find.text('沒有刪除的紀錄'), findsOneWidget);
  });

  testWidgets('the days left count down and never go below zero', (
    tester,
  ) async {
    final today = DateTime.utc(2026, 11, 19);
    final ledger = Ledger(
      today: today,
      accounts: const [Account('bank', '銀行', AccountKind.bank, 0)],
      categories: const [],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
      trash: [
        Trashed(
          Entry(
            id: 'old',
            date: DateTime.utc(2026, 9, 1),
            type: EntryType.expense,
            amount: 120,
            account: 'bank',
            category: '',
            note: '早就刪了',
          ),
          today.subtract(const Duration(days: 40)),
        ),
      ],
    );
    await show(tester, ledger);
    expect(find.textContaining('還剩 0 天'), findsOneWidget);
  });
}
