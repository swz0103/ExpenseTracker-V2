import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/design_system.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

/// 分類 in the demo book: 支出 and 收入 each with their own categories,
/// a category added, archived and brought back from 已封存, merged into
/// another, and one dragged by a long press to another place, each kept
/// in the book.
void main() {
  setUpAll(loadFonts);

  late Ledger ledger;

  Future<void> open(WidgetTester tester) async {
    ledger = demoLedger();
    await show(tester, 390, 1, book: ledger);
    await go(tester, ['更多', '分類']);
  }

  /// The open top-level categories of a side, in their order.
  List<String> tops({bool income = false}) => [
    for (final c in ledger.categories.forEntries(income: income))
      if (c.parent == null) c.name,
  ];

  testWidgets('支出 shows the spending categories and 收入 the income ones, '
      'each with how many it has', (tester) async {
    await open(tester);
    final spending = tops().length;
    final income = tops(income: true).length;
    expect(find.bySemanticsLabel('支出 $spending 個'), findsOneWidget);
    expect(find.bySemanticsLabel('收入 $income 個'), findsOneWidget);
    expect(find.text('居家生活'), findsOneWidget);
    expect(find.text('薪資收入'), findsNothing);

    await go(tester, ['收入 $income 個']);
    expect(find.text('薪資收入'), findsOneWidget);
    expect(find.text('股息收入'), findsOneWidget);
    expect(find.text('居家生活'), findsNothing);
  });

  testWidgets('新增 on 收入 keeps an income category with its name', (
    tester,
  ) async {
    await open(tester);
    await go(tester, ['收入 ${tops(income: true).length} 個', '新增']);
    expect(find.text('新增收入分類'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  獎金  ');
    await go(tester, ['儲存']);
    final made = ledger.category('獎金');
    expect(made.income, isTrue);
    expect(made.parent, isNull);
    expect(tops(income: true), contains('獎金'));
    expect(find.text('獎金'), findsOneWidget, reason: 'its tile');
  });

  testWidgets('a new category with a name already used says so and is not '
      'kept; 取消 leaves the book as it was', (tester) async {
    await open(tester);
    final before = ledger.categories.all.length;
    await go(tester, ['新增']);
    expect(find.text('新增支出分類'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '居家生活');
    await go(tester, ['儲存']);
    expect(find.text('已經有「居家生活」這個分類，可以改用合併'), findsOneWidget);
    expect(ledger.categories.all.length, before);

    // No name: 儲存 does nothing.
    await tester.enterText(find.byType(TextField), '   ');
    await go(tester, ['儲存']);
    expect(find.text('新增支出分類'), findsOneWidget);

    await go(tester, ['取消']);
    expect(find.text('新增支出分類'), findsNothing);
    expect(ledger.categories.all.length, before);
  });

  testWidgets('封存 moves a category under 已封存, and tapping it there '
      'brings it back', (tester) async {
    await open(tester);
    expect(find.text('已封存'), findsNothing);
    await go(tester, ['交通通勤', '封存']);
    expect(ledger.category('交通通勤').archived, isTrue);
    expect(tops(), isNot(contains('交通通勤')));
    expect(find.text('已封存'), findsOneWidget);

    await tester.tap(find.byTooltip('恢復「交通通勤」'));
    await tester.pumpAndSettle();
    expect(ledger.category('交通通勤').archived, isFalse);
    expect(find.text('已封存'), findsNothing);
  });

  testWidgets('合併 moves a category\'s entries into the one picked and '
      'takes it away', (tester) async {
    await open(tester);
    final moved = [
      for (final e in ledger.entries.all)
        if (e.category == '交通通勤') e.id,
    ];
    expect(moved, isNotEmpty);
    await go(tester, ['交通通勤', '合併']);
    expect(find.text('把「交通通勤」合併到'), findsOneWidget);
    await go(tester, ['^購物休閒']);
    expect(tops(), isNot(contains('交通通勤')));
    for (final id in moved) {
      expect(ledger.entries.all.firstWhere((e) => e.id == id).category, '購物休閒');
    }
  });

  testWidgets('a category changed in the editor keeps its new name, icon '
      'and colour', (tester) async {
    await open(tester);
    final before = ledger.category('訂閱服務');
    await go(tester, ['訂閱服務', '換圖示']);
    final icons = find.byType(IconChoiceButton);
    expect(icons, findsWidgets);
    await tester.tap(icons.at(3));
    await tester.pumpAndSettle();
    expect(icons, findsNothing, reason: 'closed once one is chosen');
    // A colour other than its own.
    final swatches = find.byType(SwatchButton);
    await tester.tap(swatches.at(5));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '訂閱');
    await go(tester, ['儲存']);
    final after = ledger.category('訂閱');
    expect(ledger.categories.all.any((c) => c.name == '訂閱服務'), isFalse);
    expect(after.icon, isNot(before.icon));
    expect(after.color, isNot(before.color));
    expect(find.text('訂閱'), findsOneWidget);
  });

  testWidgets('a category put under another shows as a count on that '
      'one\'s tile', (tester) async {
    await open(tester);
    await go(tester, ['交通通勤', '放在哪個分類下']);
    expect(find.text('放在哪個分類下'), findsWidgets);
    await go(tester, ['^居家生活']);
    expect(find.text('居家生活 ›'), findsOneWidget);
    await go(tester, ['儲存']);
    expect(ledger.category('交通通勤').parent, '居家生活');
    expect(tops(), isNot(contains('交通通勤')));
    expect(find.bySemanticsLabel('居家生活，1 個子分類'), findsOneWidget);
  });

  testWidgets('＋子分類 adds one under the category, and tapping it there '
      'edits it', (tester) async {
    await open(tester);
    await go(tester, ['居家生活', '^子分類']);
    expect(find.text('新增子分類'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '水電');
    await go(tester, ['^儲存']);
    expect(ledger.category('水電').parent, '居家生活');
    // Back on the parent's editor, the new one is among its tiles.
    expect(find.text('水電'), findsOneWidget);

    await go(tester, ['^水電']);
    expect(find.text('編輯分類'), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).last, '水電瓦斯');
    await go(tester, ['^儲存']);
    expect(ledger.category('水電瓦斯').parent, '居家生活');
    expect(find.text('水電瓦斯'), findsOneWidget);
  });

  testWidgets('a long press picks a category up, and dropping it on '
      'another puts it in that place', (tester) async {
    await open(tester);
    final before = tops();
    final first = before.first;
    final third = before[2];
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(first)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(find.text(third).first));
    await tester.pump();
    await gesture.moveBy(const Offset(2, 2));
    await tester.pump();
    await gesture.up();
    // Known fault, kept in view: the tile picked up was rebuilt as its
    // faded copy, and its press effect still hears the finger lift
    // (Pressable's setState after dispose). Expect null once fixed.
    expect(
      tester.takeException().toString(),
      contains('setState() called after dispose()'),
    );
    await tester.pumpAndSettle();
    expect(tops().indexOf(first), 2);
    expect(tops().length, before.length);
  });
}
