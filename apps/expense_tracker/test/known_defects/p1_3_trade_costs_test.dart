// Work package 1.3: trade amounts are worked out in one place.
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:expense_tracker/src/features/entries/model/compose_form.dart';
import 'package:expense_tracker/src/features/investments/ui/holding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../baseline/baseline_ledger.dart';
import 'known_defect.dart';

Ledger book(List<Entry> entries) => ledgerOf(
  today: day(2026, 10, 10),
  accounts: const [Account('bank', '銀行', AccountKind.bank, 5000000)],
  entries: entries,
);

void main() {
  test(
    'ENT-01: editing the shares of a buy works the broker fee out again',
    () {
      // 1000 shares at 600.5 = 600,500; fee 600500 x 0.000855 = 513.4 -> 513.
      final bought = entryOf(
        'b',
        day(2026, 10, 1),
        EntryType.buy,
        600500,
        'bank',
        holding: '2330',
        shares: 1000,
        fee: 513,
      );
      final form = ComposeForm(
        book([bought]),
        type: EntryType.buy,
        editing: bought,
      )..setShares(2000);
      // 2000 shares at 600.5 = 1,201,000; fee x 0.000855 = 1026.8 -> 1026.
      expect(form.amount, 1201000);
      expect(form.build().fee, 1026);
    },
  );

  test('ENT-01: editing the shares of a sale works fee and tax out again', () {
    final ledgerEntries = [
      entryOf(
        'b',
        day(2026, 9, 1),
        EntryType.buy,
        1000000,
        'bank',
        holding: '2330',
        shares: 2000,
      ),
      entryOf(
        's',
        day(2026, 10, 1),
        EntryType.sell,
        1000000,
        'bank',
        holding: '2330',
        shares: 1000,
        fee: 855,
        tax: 3000,
      ),
    ];
    final sold = ledgerEntries.last;
    final form = ComposeForm(
      book(ledgerEntries),
      type: EntryType.sell,
      editing: sold,
    )..setShares(500);
    // 500 shares at 1000 = 500,000: fee 500000 x 0.000855 = 427.5 -> 427,
    // tax 500000 x 0.003 = 1500.
    expect(form.amount, 500000);
    expect(form.build().fee, 427);
    expect(form.build().tax, 1500);
  });

  testWidgets(
    'INV-01: the holding page shows a sale at what reached the account',
    (tester) async {
      tester.view.physicalSize = const Size(420, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ledger = book([
        entryOf(
          'b',
          day(2026, 10, 1),
          EntryType.buy,
          900000,
          'bank',
          holding: '2330',
          shares: 1000,
          fee: 100,
        ),
        entryOf(
          's',
          day(2026, 10, 9),
          EntryType.sell,
          1000000,
          'bank',
          holding: '2330',
          shares: 1000,
          fee: 855,
          tax: 3000,
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: HoldingPage(
              ledger: ledger,
              code: '2330',
              nav: Nav(
                open: (_) {},
                back: () {},
                compose: ({type = EntryType.expense, entry, draft}) async {},
                showEntry: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final texts = [
        for (final w in find.byType(Text).evaluate())
          (w.widget as Text).data ?? '',
      ];
      // 1,000,000 - 855 fee - 3,000 tax = 996,145 reached the bank.
      expect(texts, contains('+996,145'));
      expect(texts, isNot(contains('+999,145')));
    },
  );

  test('ENT-08: the cost preview of an old sale uses the lots of that day', () {
    final entries = [
      entryOf(
        'b1',
        day(2026, 1, 5),
        EntryType.buy,
        100000,
        'bank',
        holding: '2330',
        shares: 1000,
      ),
      entryOf(
        's1',
        day(2026, 2, 5),
        EntryType.sell,
        150000,
        'bank',
        holding: '2330',
        shares: 1000,
      ),
      entryOf(
        'b2',
        day(2026, 3, 5),
        EntryType.buy,
        200000,
        'bank',
        holding: '2330',
        shares: 1000,
      ),
    ];
    final form = ComposeForm(
      book(entries),
      type: EntryType.sell,
      editing: entries[1],
    );
    // On Feb 5 the 1000 shares sold cost the first buy, 100,000; the
    // later 200,000 lot was not yet held.
    expect(form.saleCost, 100000);
  }, skip: knownDefect('ENT-08', '1.3'));
}
