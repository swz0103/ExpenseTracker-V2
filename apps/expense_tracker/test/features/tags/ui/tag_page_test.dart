import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/design_system/display/date.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

/// A tag's page and a merchant's in the demo book, with a second tag
/// #旅行 added: their entries, and 改名, 合併到… and 刪除 from the ⋯ (each
/// told with 復原, not asked first: D82),
/// each kept on the entries themselves.
void main() {
  setUpAll(loadFonts);

  late Ledger ledger;

  /// The demo book with two trips tagged #旅行.
  Ledger book() {
    final book = demoLedger();
    for (final (id, day, amount) in [
      ('trip-1', 20, 2400),
      ('trip-2', 22, 900),
    ]) {
      book.entryCommands.add(
        Entry(
          id: id,
          date: DateTime.utc(2026, 9, day),
          type: EntryType.expense,
          amount: amount,
          account: 'bank',
          category: '交通通勤',
          note: '高鐵',
          tags: const ['旅行'],
        ),
      );
    }
    return book;
  }

  Future<void> open(WidgetTester tester, List<String> path) async {
    ledger = book();
    await show(tester, 390, 1, book: ledger);
    await go(tester, ['更多', '標籤與商家', ...path]);
  }

  /// The ids of the entries carrying [tag].
  Set<String> tagged(String tag) => {
    for (final e in ledger.entries.all)
      if (e.tags.contains(tag)) e.id,
  };

  /// The ids of the entries at [merchant].
  Set<String> at(String merchant) => {
    for (final e in ledger.entries.all)
      if (e.merchant == merchant) e.id,
  };

  /// Types [name] in the rename sheet and presses 完成 on the keyboard.
  Future<void> rename(WidgetTester tester, String name) async {
    await go(tester, ['~更多選項', '改名']);
    await tester.enterText(find.byType(TextField), name);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('a tag\'s page lists its entries, and one tapped opens', (
    tester,
  ) async {
    await open(tester, ['#旅行']);
    expect(find.text('#旅行'), findsWidgets);
    expect(find.text('紀錄 · 2 筆'), findsOneWidget);
    expect(find.text('交通通勤 · 9/22'), findsOneWidget);
    expect(find.text('交通通勤 · 9/20'), findsOneWidget);
    await go(tester, ['高鐵']);
    expect(find.byKey(Keys.discard), findsOneWidget, reason: 'the entry');
  });

  testWidgets('a tag\'s categories are each said as a whole percent of '
      'what it spent (review 16: percent call sites)', (tester) async {
    ledger = book()
      ..entryCommands.add(
        Entry(
          id: 'trip-3',
          date: DateTime.utc(2026, 9, 21),
          type: EntryType.expense,
          amount: 1100,
          account: 'bank',
          category: '居家生活',
          tags: const ['旅行'],
        ),
      );
    await show(tester, 390, 1, book: ledger);
    await go(tester, ['更多', '標籤與商家', '#旅行']);
    // 2,400 + 900 = 3,300 on 交通通勤 and 1,100 on 居家生活, of 4,400:
    // 75% and 25%.
    expect(find.text('交通通勤 75%'), findsOneWidget);
    expect(find.text('居家生活 25%'), findsOneWidget);
  });

  testWidgets('改名 a tag moves its entries to the new name, a # typed '
      'before it left out', (tester) async {
    await open(tester, ['#旅行']);
    final trips = tagged('旅行');
    await rename(tester, '#出遊');
    expect(tagged('旅行'), isEmpty);
    expect(tagged('出遊'), trips);
    expect(find.text('#出遊'), findsWidgets, reason: 'its page now');
  });

  testWidgets('改名 to a tag already used merges at once, with 復原 (D82)', (
    tester,
  ) async {
    await open(tester, ['#旅行']);
    final trips = tagged('旅行');
    final home = tagged('家用');
    await rename(tester, '家用');
    expect(find.byKey(Keys.confirm), findsNothing);
    expect(tagged('旅行'), isEmpty);
    expect(tagged('家用'), {...trips, ...home});
    expect(find.text('已把「#旅行」合併到「#家用」'), findsOneWidget);
    await tester.tap(find.byKey(Keys.snack('復原')));
    await tester.pumpAndSettle();
    expect(tagged('旅行'), trips);
    expect(tagged('家用'), home);
  });

  testWidgets('改名 to the same name changes nothing', (tester) async {
    await open(tester, ['#旅行']);
    final trips = tagged('旅行');
    await rename(tester, '旅行');
    expect(tagged('旅行'), trips);
    expect(find.byKey(Keys.snack('復原')), findsNothing);
  });

  testWidgets('合併到… picks another tag and moves the entries there', (
    tester,
  ) async {
    await open(tester, ['#家用']);
    final both = {...tagged('旅行'), ...tagged('家用')};
    await go(tester, ['~更多選項', '合併到…']);
    expect(find.text('合併到'), findsOneWidget);
    await go(tester, ['^#旅行']);
    expect(find.byKey(Keys.confirm), findsNothing);
    expect(tagged('家用'), isEmpty);
    expect(tagged('旅行'), both);
    expect(find.text('#旅行'), findsWidgets, reason: 'opened on the one kept');
    expect(find.text('已把「#家用」合併到「#旅行」'), findsOneWidget);
  });

  testWidgets('刪除標籤 takes the tag off its entries and keeps them; 復原 '
      'puts it back', (tester) async {
    await open(tester, ['#旅行']);
    final trips = tagged('旅行');
    final count = ledger.entries.all.length;
    await go(tester, ['~更多選項', '刪除標籤']);
    expect(find.byKey(Keys.confirm), findsNothing);
    expect(tagged('旅行'), isEmpty);
    expect(ledger.entries.all.length, count);
    expect(find.text('紀錄 · 2 筆'), findsNothing, reason: 'back on 標籤');
    expect(find.text('已刪除「#旅行」'), findsOneWidget);
    await tester.tap(find.byKey(Keys.snack('復原')));
    await tester.pumpAndSettle();
    expect(tagged('旅行'), trips);
  });

  testWidgets('a merchant\'s page says how often, when last and first', (
    tester,
  ) async {
    await open(tester, ['商家', '星巴克']);
    final visits = at('星巴克').length;
    expect(find.text('去過'), findsOneWidget);
    expect(find.text('$visits 次', findRichText: true), findsOneWidget);
    final first = [
      for (final e in ledger.entries.all)
        if (e.merchant == '星巴克') e.date,
    ].reduce((a, b) => a.isBefore(b) ? a : b);
    expect(find.text('最近 10/4 · 第一次 ${formatYMd(first)}'), findsOneWidget);
    expect(find.text('紀錄'), findsWidgets);
  });

  testWidgets('改名 a merchant to another merges them at once', (tester) async {
    await open(tester, ['商家', '星巴克']);
    final both = {...at('星巴克'), ...at('家樂福')};
    await rename(tester, '家樂福');
    expect(find.byKey(Keys.confirm), findsNothing);
    expect(at('星巴克'), isEmpty);
    expect(at('家樂福'), both);
    expect(find.text('已把「星巴克」合併到「家樂福」'), findsOneWidget);
  });

  testWidgets('刪除商家 takes the merchant off its entries; 復原 puts it '
      'back', (tester) async {
    await open(tester, ['商家', 'Apple']);
    final apple = at('Apple');
    await go(tester, ['~更多選項', '刪除商家']);
    expect(find.byKey(Keys.confirm), findsNothing);
    expect(at('Apple'), isEmpty);
    expect(
      ledger.entries.all.where((e) => e.note == 'iPhone 17'),
      hasLength(1),
    );
    expect(find.text('已刪除「Apple」'), findsOneWidget);
    await tester.tap(find.byKey(Keys.snack('復原')));
    await tester.pumpAndSettle();
    expect(at('Apple'), apple);
  });
}
