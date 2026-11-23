/// Checks the investment fields of the composer: a buy, a sale and a
/// dividend are recorded with the shares, price, fee, tax and premium
/// shown and changed on them; a sale of more than is held and a capital
/// reduction past the holding are refused; shares given or taken away
/// change the holding.
library;

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/formatting/words.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/entries/forms/composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

void main() {
  late Ledger ledger;
  setUp(() => ledger = demoLedger());

  /// Opens the composer as 記一筆 does, on the tab of [type].
  Future<void> open(
    WidgetTester tester, {
    EntryType type = EntryType.expense,
    Entry? draft,
  }) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  openComposer(context, ledger, type: type, draft: draft),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String digits) async {
    for (final key in ['C', ...digits.split(''), Words.done]) {
      await tester.tap(find.byKey(Keys.calc(key)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(Keys.save));
    await tester.pumpAndSettle();
  }

  List<Entry> added(int before) => ledger.entries.all.skip(before).toList();

  /// 投資 with [code] picked, [shares] at [price].
  Future<void> trade(
    WidgetTester tester,
    String code,
    String shares,
    String price,
  ) async {
    await go(tester, [code, '股數']);
    await type(tester, shares);
    await go(tester, ['成交價']);
    await type(tester, price);
  }

  testWidgets('a buy is recorded with its shares, price and the fee changed', (
    tester,
  ) async {
    final count = ledger.entries.length;
    final held = ledger.holding('2330')!.shares;
    await open(tester, type: EntryType.buy);
    await trade(tester, '2330 台積電', '1000', '1000');
    // What it comes to: the trade and the broker's fee worked out.
    expect(find.text('1,000,855'), findsOneWidget);
    await go(tester, ['手續費 855', '手續費（試算）']);
    await type(tester, '500');
    expect(find.bySemanticsLabel('手續費：500'), findsOneWidget);
    expect(find.text('1,000,500'), findsOneWidget);
    await save(tester);
    final made = added(count).single;
    expect(
      (made.type, made.holding, made.shares, made.amount, made.fee),
      (EntryType.buy, '2330', 1000, 1000000, 500),
    );
    expect(ledger.holding('2330')!.shares, held + 1000);
  });

  /// A buy of 1,000 shares for 1,000,000 begun on [date], its fee not
  /// yet set (0).
  Entry buyOn(DateTime date) => Entry(
    id: '',
    date: date,
    type: EntryType.buy,
    amount: 1000000,
    account: 'broker',
    holding: '2330',
    shares: 1000,
  );

  testWidgets('a trade before a holiday settles after it (D24)', (
    tester,
  ) async {
    // Wed 2026-10-07: Thu 10-08 is day 1, Fri 10-09 is 補假, then the
    // weekend, so Mon 10-12 is day 2.
    await open(tester, draft: buyOn(DateTime.utc(2026, 10, 7)));
    await go(tester, ['手續費 0']);
    expect(find.text('10/12'), findsOneWidget);
    expect(find.textContaining('未含國定假日'), findsNothing);
  });

  testWidgets('a trade in a year with no holidays on record says so', (
    tester,
  ) async {
    // Wed 2028-01-05 + 2 weekdays = Fri 01-07; 2028 is in no table.
    await open(tester, draft: buyOn(DateTime.utc(2028, 1, 5)));
    await go(tester, ['手續費 0']);
    expect(find.text('1/7（未含國定假日）'), findsOneWidget);
  });

  testWidgets('a sale shows what it made and is recorded with its tax', (
    tester,
  ) async {
    final count = ledger.entries.length;
    final held = ledger.holding('2330')!.shares;
    await open(tester, type: EntryType.sell);
    await go(tester, ['賣出']);
    await trade(tester, '2330 台積電', '100', '1500');
    await go(tester, ['手續費', '平均成本']);
    expect(find.text('已實現損益'), findsOneWidget);
    await go(tester, ['證交稅（試算）']);
    await type(tester, '400');
    await save(tester);
    final made = added(count).single;
    expect(
      (made.type, made.shares, made.amount, made.tax),
      (EntryType.sell, 100, 150000, 400),
    );
    expect(ledger.holding('2330')!.shares, held - 100);
  });

  testWidgets('selling more than is held is refused', (tester) async {
    final count = ledger.entries.length;
    final held = ledger.holding('2330')!.shares;
    await open(tester);
    await go(tester, ['投資', '賣出']);
    await trade(tester, '2330 台積電', '${held + 1}', '1000');
    await save(tester);
    expect(find.text('賣出股數超過持股'), findsOneWidget);
    expect(ledger.entries.length, count);
  });

  testWidgets('a dividend is recorded with its premium', (tester) async {
    final count = ledger.entries.length;
    await open(tester, type: EntryType.dividend);
    await go(tester, ['股息', '0056 高股息', '股息金額']);
    await type(tester, '30000');
    // Over 20,000, the premium is worked out: 2.11%.
    await go(tester, ['二代健保 633']);
    await go(tester, ['二代健保：633']);
    await type(tester, '600');
    await save(tester);
    final made = added(count).single;
    expect(
      (made.type, made.holding, made.amount, made.tax, made.shares),
      (EntryType.dividend, '0056', 30000, 600, 0),
    );
  });

  testWidgets('shares given as a dividend are added to the holding', (
    tester,
  ) async {
    final held = ledger.holding('0056')!.shares;
    await open(tester, type: EntryType.dividend);
    await go(tester, ['股息', '0056 高股息', '股息金額']);
    await type(tester, '100');
    await go(tester, ['配股、二代健保、備註', '配股', '配股增加']);
    await type(tester, '50');
    await save(tester);
    expect(ledger.holding('0056')!.shares, held + 50);
  });

  testWidgets('a capital reduction takes shares away, no more than held', (
    tester,
  ) async {
    final count = ledger.entries.length;
    final held = ledger.holding('0056')!.shares;
    await open(tester, type: EntryType.dividend);
    await go(tester, ['股息', '0056 高股息', '配股、二代健保、備註', '減資', '減資減少']);
    await type(tester, '${held + 1}');
    await save(tester);
    expect(find.textContaining('減少的股數超過持股'), findsOneWidget);
    await go(tester, ['減資減少']);
    await type(tester, '10');
    await save(tester);
    expect(added(count).single.shares, -10);
    expect(ledger.holding('0056')!.shares, held - 10);
  });

  testWidgets('a stock from the whole list is the one traded', (tester) async {
    final count = ledger.entries.length;
    await open(tester, type: EntryType.buy);
    await go(tester, ['全部標的', '2603']);
    await go(tester, ['股數']);
    await type(tester, '1');
    await go(tester, ['成交價']);
    await type(tester, '200');
    await save(tester);
    expect(added(count).single.holding, '2603');
  });
}
