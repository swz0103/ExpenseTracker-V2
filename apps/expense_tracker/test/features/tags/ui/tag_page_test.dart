import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/design_system/display/date.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

/// A tag's page and a merchant's in the demo book, with a second tag
/// #旅行 added: their entries, and 改名, 合併到… and 移除 from the ⋯,
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

  testWidgets('改名 a tag moves its entries to the new name, a # typed '
      'before it left out', (tester) async {
    await open(tester, ['#旅行']);
    final trips = tagged('旅行');
    await rename(tester, '#出遊');
    expect(tagged('旅行'), isEmpty);
    expect(tagged('出遊'), trips);
    expect(find.text('#出遊'), findsWidgets, reason: 'its page now');
  });

  testWidgets('改名 to a tag already used asks first, and merges on 合併', (
    tester,
  ) async {
    await open(tester, ['#旅行']);
    final both = {...tagged('旅行'), ...tagged('家用')};
    await rename(tester, '家用');
    expect(find.text('合併到 #家用？'), findsOneWidget);
    expect(find.text('旅行 的 2 筆紀錄會改成 #家用，#旅行 就不見了。'), findsOneWidget);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(tagged('旅行'), isEmpty);
    expect(tagged('家用'), both);
  });

  testWidgets('改名 to a tag already used, then 取消, changes nothing; nor '
      'does the same name', (tester) async {
    await open(tester, ['#旅行']);
    final trips = tagged('旅行');
    await rename(tester, '家用');
    await go(tester, ['取消']);
    expect(tagged('旅行'), trips);
    await rename(tester, '旅行');
    expect(tagged('旅行'), trips);
    expect(find.text('合併到 #旅行？'), findsNothing);
  });

  testWidgets('合併到… picks another tag and moves the entries there', (
    tester,
  ) async {
    await open(tester, ['#家用']);
    final both = {...tagged('旅行'), ...tagged('家用')};
    await go(tester, ['~更多選項', '合併到…']);
    expect(find.text('合併到'), findsOneWidget);
    await go(tester, ['^#旅行']);
    expect(find.textContaining('合併到 #旅行？'), findsOneWidget);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(tagged('家用'), isEmpty);
    expect(tagged('旅行'), both);
    expect(find.text('#旅行'), findsWidgets, reason: 'opened on the one kept');
  });

  testWidgets('移除標籤 takes the tag off its entries and keeps them', (
    tester,
  ) async {
    await open(tester, ['#旅行']);
    final count = ledger.entries.all.length;
    await go(tester, ['~更多選項', '移除標籤']);
    expect(find.text('移除 #旅行？'), findsOneWidget);
    expect(find.text('2 筆紀錄會拿掉這個標籤，紀錄本身保留。'), findsOneWidget);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(tagged('旅行'), isEmpty);
    expect(ledger.entries.all.length, count);
    expect(find.text('紀錄 · 2 筆'), findsNothing, reason: 'back on 標籤');
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

  testWidgets('改名 a merchant to another merges them once agreed', (
    tester,
  ) async {
    await open(tester, ['商家', '星巴克']);
    final both = {...at('星巴克'), ...at('家樂福')};
    await rename(tester, '家樂福');
    expect(find.textContaining('合併到 家樂福？'), findsOneWidget);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(at('星巴克'), isEmpty);
    expect(at('家樂福'), both);
  });

  testWidgets('移除商家 takes the merchant off its entries', (tester) async {
    await open(tester, ['商家', 'Apple']);
    await go(tester, ['~更多選項', '移除商家']);
    expect(find.text('移除 Apple？'), findsOneWidget);
    expect(find.text('1 筆紀錄會拿掉這個商家，紀錄本身保留。'), findsOneWidget);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(at('Apple'), isEmpty);
    expect(
      ledger.entries.all.where((e) => e.note == 'iPhone 17'),
      hasLength(1),
    );
  });
}
