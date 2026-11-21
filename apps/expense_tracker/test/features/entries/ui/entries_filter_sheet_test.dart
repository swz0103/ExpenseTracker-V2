/// Checks 篩選 on the record list: what is picked on the sheet is the
/// filter applied, 清除 and 取消 leave nothing narrowed, and a filter shows
/// just the entries of its kind, days, amounts, account and category.
library;

import 'dart:ui' show Tristate;

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/entries/ui/entries_filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

void main() {
  late Ledger ledger;
  setUp(() => ledger = demoLedger());

  /// Opens 篩選 over [current]; what it gives back is in the list.
  Future<List<EntryFilter?>> open(
    WidgetTester tester, [
    EntryFilter current = const EntryFilter(),
  ]) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final got = <EntryFilter?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  got.add(await showLedgerFilter(context, ledger, current)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return got;
  }

  testWidgets('a kind, an account, a category and bounds on the amount are '
      'applied together', (tester) async {
    final got = await open(tester);
    await go(tester, ['支出', '帳戶', '日常銀行', '分類', '居家生活']);
    await tester.enterText(find.byType(TextField).first, ' 100 ');
    await tester.enterText(find.byType(TextField).last, '5000');
    await go(tester, ['套用']);
    final filter = got.single!;
    expect(filter.kind, KindFilter.expense);
    expect(filter.account, 'bank');
    expect(filter.category, '居家生活');
    expect((filter.least, filter.most), (100, 5000));
    expect(filter.range, isNull);
    expect(filter.count, 4);
    expect(filter.amountLabel, '金額 100–5,000');
  });

  testWidgets('the account and category chosen are shown and can be put '
      'back to all', (tester) async {
    final got = await open(
      tester,
      const EntryFilter(account: 'bank', category: '居家生活'),
    );
    expect(find.text('日常銀行'), findsOneWidget);
    expect(find.text('居家生活'), findsOneWidget);
    await tester.tap(find.byTooltip('改回全部帳戶'));
    await tester.tap(find.byTooltip('改回全部分類'));
    await tester.pumpAndSettle();
    await go(tester, ['套用']);
    expect(got.single!.count, 0);
  });

  testWidgets('近 7 天 ends today and starts six days before', (tester) async {
    final got = await open(tester);
    await go(tester, ['近 7 天', '套用']);
    final range = got.single!.range!;
    expect(range.end, DateTime(2026, 10, 4));
    expect(range.start, DateTime(2026, 9, 28));
  });

  testWidgets('a quick span opened again is shown chosen, and 依月份 lets it '
      'go', (tester) async {
    final thirty = DateTimeRange(
      start: DateTime(2026, 9, 5),
      end: DateTime(2026, 10, 4),
    );
    final got = await open(tester, EntryFilter(range: thirty));
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('近 30 天'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    semantics.dispose();
    await go(tester, ['依月份', '套用']);
    expect(got.single!.range, isNull);
  });

  testWidgets('自訂 picks days on the calendar and shows them on the sheet', (
    tester,
  ) async {
    final got = await open(tester);
    await go(tester, ['自訂', '上月', '確定']);
    expect(find.text('9/1–9/30'), findsOneWidget);
    await go(tester, ['套用']);
    final range = got.single!.range!;
    expect(
      (range.start, range.end),
      (DateTime(2026, 9), DateTime(2026, 9, 30)),
    );
    expect(EntryFilter.rangeLabel(range), '9/1–9/30');
  });

  testWidgets('清除 sets everything back to all', (tester) async {
    final got = await open(
      tester,
      EntryFilter(
        kind: KindFilter.income,
        account: 'bank',
        category: '居家生活',
        range: DateTimeRange(
          start: DateTime(2026, 9),
          end: DateTime(2026, 9, 3),
        ),
        least: 5,
        most: 9,
      ),
    );
    expect(find.text('5'), findsOneWidget);
    await go(tester, ['清除', '套用']);
    final filter = got.single!;
    expect(filter.count, 0);
    expect(filter.least, isNull);
  });

  testWidgets('取消 gives no filter back', (tester) async {
    final got = await open(tester);
    await go(tester, ['收入', '取消']);
    expect(got, [null]);
  });

  group('a filter shows', () {
    final day = DateTime.utc(2026, 10, 4);
    Entry e(
      EntryType type, {
      int amount = 100,
      String account = 'bank',
      String category = '居家生活',
      String? to,
      DateTime? date,
      List<(String, int)> parts = const [],
    }) => Entry(
      id: 'x',
      date: date ?? day,
      type: type,
      amount: amount,
      account: account,
      category: category,
      to: to,
      holding: type == EntryType.dividend ? '2330' : null,
      parts: parts,
    );

    test('only entries of its kind; dividends count as income', () {
      final spend = e(EntryType.expense);
      final paid = e(EntryType.dividend);
      final moved = e(EntryType.transfer, category: '', to: 'cash');
      expect(KindFilter.income.shows(paid), isTrue);
      expect(KindFilter.income.shows(spend), isFalse);
      expect(KindFilter.investment.shows(paid), isTrue);
      expect(KindFilter.transfer.shows(moved), isTrue);
      expect(KindFilter.all.shows(moved), isTrue);
    });

    test('only days inside its span, whatever the hour', () {
      final filter = EntryFilter(
        range: DateTimeRange(
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 3),
        ),
      );
      final ledger = demoLedger();
      expect(
        filter.shows(
          ledger,
          e(EntryType.expense, date: DateTime.utc(2026, 10, 3, 23)),
        ),
        isTrue,
      );
      expect(filter.shows(ledger, e(EntryType.expense)), isFalse);
      expect(
        filter.shows(
          ledger,
          e(EntryType.expense, date: DateTime.utc(2026, 9, 30)),
        ),
        isFalse,
      );
    });

    test('amounts within its bounds only', () {
      final ledger = demoLedger();
      const filter = EntryFilter(least: 100, most: 200);
      expect(filter.shows(ledger, e(EntryType.expense, amount: 99)), isFalse);
      expect(filter.shows(ledger, e(EntryType.expense, amount: 200)), isTrue);
      expect(filter.shows(ledger, e(EntryType.expense, amount: 201)), isFalse);
      expect(const EntryFilter(least: 3).amountLabel, '金額 3 以上');
      expect(const EntryFilter(most: 3).amountLabel, '金額 3 以下');
      expect(const EntryFilter().amountLabel, '');
    });

    test('money into its account as well as out of it', () {
      final ledger = demoLedger();
      const filter = EntryFilter(account: 'cash');
      expect(
        filter.shows(ledger, e(EntryType.transfer, category: '', to: 'cash')),
        isTrue,
      );
      expect(filter.shows(ledger, e(EntryType.expense)), isFalse);
    });

    test('its category, and a split part in it', () {
      final ledger = demoLedger();
      const filter = EntryFilter(category: '飲食日常');
      expect(filter.shows(ledger, e(EntryType.expense)), isFalse);
      expect(
        filter.shows(
          ledger,
          e(EntryType.expense, parts: const [('居家生活', 60), ('飲食日常', 40)]),
        ),
        isTrue,
      );
    });

    test('each narrowing taken away on its own', () {
      final full = EntryFilter(
        kind: KindFilter.expense,
        account: 'bank',
        category: '居家生活',
        range: DateTimeRange(start: DateTime(2026), end: DateTime(2026, 2)),
        least: 1,
        most: 2,
      );
      expect(full.count, 5);
      expect(full.withoutAccount().account, isNull);
      expect(full.withoutAccount().count, 4);
      expect(full.withoutCategory().category, isNull);
      expect(full.withoutRange().range, isNull);
      expect(full.withoutAmounts().boundsAmount, isFalse);
      expect(full.withKind(KindFilter.all).count, 4);
    });
  });
}
