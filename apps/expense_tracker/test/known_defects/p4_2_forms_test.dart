// Work package 4.2: forms keep what the person typed.
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/formatting/words.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/entries/forms/composer.dart';
import 'package:expense_tracker/src/features/entries/model/compose_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../baseline/baseline_ledger.dart';
import 'known_defect.dart';

Ledger book(List<Entry> entries) => ledgerOf(
  today: day(2026, 10, 4),
  accounts: const [
    Account('bank', '銀行', AccountKind.bank, 100000),
    Account('cash', '現金', AccountKind.cash, 2000),
    Account('card', '信用卡', AccountKind.card, 0),
    Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
  ],
  categories: [
    Category('飲食', 'food', 0xFF5C9A83),
    Category('居家', 'home', 0xFF5B8DB0),
    Category('交通', 'car', 0xFF5C9A83),
  ],
  entries: entries,
);

void main() {
  test(
    'ENT-02: switching to a foreign account does not drop a split silently',
    () {
      final form = ComposeForm(book(const []), type: EntryType.expense)
        ..setAmount(300)
        ..category = '飲食'
        ..toggleSplit()
        ..setPart(0, 200)
        ..addPart('居家');
      form
        ..account = 'usd'
        ..home = 9500;
      final built = form.build();
      // Either the form still holds the split and the entry keeps it, or
      // the form let go of it and no longer shows one.
      expect(built.parts.isNotEmpty, form.parts != null);
    },
    skip: knownDefect('ENT-02', '4.2'),
  );

  group('ENT-03: closing 記一筆 with something typed', () {
    Future<Ledger> open(WidgetTester tester) async {
      final ledger = demoLedger();
      tester.view.physicalSize = const Size(420, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openComposer(context, ledger),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('金額'));
      await tester.pumpAndSettle();
      for (final key in ['C', '1', '2', '0', Words.done]) {
        await tester.tap(find.byKey(Keys.calc(key)));
        await tester.pumpAndSettle();
      }
      return ledger;
    }

    bool kept(WidgetTester tester, Ledger ledger) {
      final shown = find.byKey(Keys.save).evaluate().isNotEmpty;
      final asked =
          find.byType(AlertDialog).evaluate().isNotEmpty ||
          find.byType(Dialog).evaluate().isNotEmpty;
      final saved = ledger.drafts.of('expense') != null;
      return shown || asked || saved;
    }

    testWidgets('the system back key asks, or keeps a draft', (tester) async {
      final ledger = await open(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(kept(tester, ledger), isTrue);
    });

    testWidgets('a tap on the scrim asks, or keeps a draft', (tester) async {
      final ledger = await open(tester);
      await tester.tapAt(const Offset(210, 20));
      await tester.pumpAndSettle();
      expect(kept(tester, ledger), isTrue);
    });
  });

  test(
    'ENT-05: picking a merchant keeps the account and category already chosen',
    () {
      final ledger = book([
        entryOf(
          'a',
          day(2026, 9, 1),
          EntryType.expense,
          100,
          'cash',
          category: '居家',
          merchant: '全聯',
        ),
      ]);
      final form = ComposeForm(ledger, type: EntryType.expense)
        ..account = 'card'
        ..pickCategory('交通')
        ..pickMerchant('全聯');
      expect(form.account, 'card');
      expect(form.category, '交通');
    },
    skip: knownDefect('ENT-05', '4.2'),
  );

  test(
    'ENT-06: editing a transfer previews balances without counting it twice',
    () {
      final moved = entryOf(
        't',
        day(2026, 10, 1),
        EntryType.transfer,
        1000,
        'bank',
        to: 'cash',
      );
      final ledger = book([moved]);
      // Bank 100000 - 1000 = 99000; cash 2000 + 1000 = 3000.
      expect(ledger.balanceService.balance('bank'), 99000);
      final form = ComposeForm(
        ledger,
        type: EntryType.transfer,
        editing: moved,
      );
      // Saving the same 1,000 again leaves the balances as they are.
      expect(form.fromAfter, 99000);
      expect(form.toAfter, 3000);
    },
    skip: knownDefect('ENT-06', '4.2'),
  );
}
