/// Checks what the composer keeps: a spending written on it is recorded
/// with the amount, category and account chosen, split over categories
/// when split; a form put aside comes back the next time; an entry looked
/// at is changed or deleted; a refund and a lending are recorded as such.
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
  late List<(ComposeOutcome, Entry)?> outcomes;
  setUp(() {
    ledger = demoLedger();
    outcomes = [];
  });

  /// Opens the composer as 記一筆 does, for [entry] or [refundOf] when
  /// given.
  Future<void> open(
    WidgetTester tester, {
    EntryType type = EntryType.expense,
    Entry? entry,
    Entry? draft,
    Entry? refundOf,
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
              onPressed: () async => outcomes.add(
                await openComposer(
                  context,
                  ledger,
                  type: type,
                  entry: entry,
                  draft: draft,
                  refundOf: refundOf,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Types [digits] on the calculator open, after clearing it.
  Future<void> type(WidgetTester tester, String digits) async {
    for (final key in ['C', ...digits.split(''), Words.done]) {
      await tester.tap(find.byKey(Keys.calc(key)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> amount(
    WidgetTester tester,
    String digits, {
    String label = '金額',
  }) async {
    await tester.tap(find.byTooltip(label));
    await tester.pumpAndSettle();
    await type(tester, digits);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(Keys.save));
    await tester.pumpAndSettle();
  }

  /// The entries added since [before] entries were in the book.
  List<Entry> added(int before) => ledger.entries.all.skip(before).toList();

  testWidgets('a spending is recorded with the amount, category and account '
      'chosen', (tester) async {
    final count = ledger.entries.length;
    await open(tester);
    await amount(tester, '120');
    await go(tester, ['全部', '購物休閒', '付款帳戶', '隨身現金']);
    expect(find.bySemanticsLabel('付款帳戶：隨身現金'), findsOneWidget);
    await save(tester);
    final made = added(count).single;
    expect(
      (made.type, made.amount, made.category, made.account),
      (EntryType.expense, 120, '購物休閒', 'cash'),
    );
    expect(outcomes.single!.$1, ComposeOutcome.saved);
  });

  testWidgets('a spending split over categories keeps each part', (
    tester,
  ) async {
    final count = ledger.entries.length;
    await open(tester);
    await amount(tester, '300');
    await go(tester, ['拆分', '居家生活', '交通通勤', '平均分配']);
    expect(find.text('✓ 剛好分完'), findsOneWidget);
    await save(tester);
    final made = added(count).single;
    expect(made.amount, 300);
    expect(made.parts.map((p) => p.$2).fold(0, (a, b) => a + b), 300);
    expect(made.parts.map((p) => p.$1), containsAll(['居家生活', '交通通勤']));
  });

  testWidgets('a part of a split is changed on its own, and what is left '
      'over said', (tester) async {
    await open(tester);
    await amount(tester, '300');
    // Split from the category it had, 飲食日常, with one more.
    await go(tester, ['拆分', '居家生活', '平均分配']);
    await go(tester, ['飲食日常\n150']);
    await type(tester, '100');
    expect(find.text('還剩 50'), findsOneWidget);
    await go(tester, ['居家生活\n150']);
    await type(tester, '250');
    expect(find.text('多了 50'), findsOneWidget);
    await save(tester);
    // Not kept while the parts do not add up.
    expect(outcomes, isEmpty);
  });

  testWidgets('a category made from the list is kept and chosen', (
    tester,
  ) async {
    final count = ledger.entries.length;
    await open(tester);
    await amount(tester, '80');
    await go(tester, ['全部', '新增']);
    await tester.enterText(find.byType(TextField).last, '寵物');
    await go(tester, ['儲存']);
    expect(ledger.categories.all.map((c) => c.name), contains('寵物'));
    await save(tester);
    expect(added(count).single.category, '寵物');
  });

  testWidgets('a form put aside comes back the next time, and 重填 clears '
      'it', (tester) async {
    await open(tester);
    await amount(tester, '456');
    await tester.tap(find.byKey(Keys.discard));
    await tester.pumpAndSettle();
    expect(outcomes, [null]);
    expect(ledger.drafts.of('expense'), isNotNull);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('−456'), findsOneWidget);
    await tester.tap(find.byTooltip('重填'));
    await tester.pumpAndSettle();
    expect(find.text('−456'), findsNothing);
    expect(ledger.drafts.of('expense'), isNull);
  });

  testWidgets('a tab keeps its own form put aside', (tester) async {
    await open(tester);
    await go(tester, ['收入']);
    await amount(tester, '900');
    await tester.tap(find.byKey(Keys.discard));
    await tester.pumpAndSettle();

    final count = ledger.entries.length;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('+900'), findsNothing);
    await go(tester, ['收入']);
    expect(find.text('+900'), findsOneWidget);
    await save(tester);
    final made = added(count).single;
    expect((made.type, made.amount), (EntryType.income, 900));
    // Recorded, the form put aside is gone.
    expect(ledger.drafts.of('income'), isNull);
  });

  testWidgets('a form half written is kept as the app leaves, and let go '
      'when it comes back', (tester) async {
    await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    // Nothing written: nothing kept.
    expect(ledger.drafts.of('expense'), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await amount(tester, '77');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(ledger.drafts.of('expense'), contains('77'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(ledger.drafts.of('expense'), isNull);
  });

  testWidgets('an entry looked at is changed with 編輯', (tester) async {
    final lunch = ledger.entries.all.firstWhere(
      (e) => e.type == EntryType.expense && e.parts.isEmpty && !e.isRefund,
    );
    await open(tester, entry: lunch);
    expect(find.text(Words.edit), findsOneWidget);
    await save(tester);
    expect(find.text('編輯中'), findsOneWidget);
    await amount(tester, '999');
    expect(find.text('儲存修改'), findsOneWidget);
    await save(tester);
    expect(ledger.entries.byId(lunch.id)!.amount, 999);
    expect(outcomes.single!.$1, ComposeOutcome.saved);
  });

  testWidgets('an entry looked at is deleted once agreed', (tester) async {
    final lunch = ledger.entries.all.firstWhere(
      (e) => e.type == EntryType.expense,
    );
    await open(tester, entry: lunch);
    await tester.tap(find.byKey(Keys.discard));
    await tester.pumpAndSettle();
    expect(find.text('刪除這一筆？'), findsOneWidget);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(outcomes.single!.$1, ComposeOutcome.deleted);
    expect(outcomes.single!.$2.id, lunch.id);
  });

  testWidgets('a spending looked at offers its refund', (tester) async {
    final lunch = ledger.entries.all.firstWhere(
      (e) =>
          e.type == EntryType.expense &&
          ledger.entryQueryService.refundable(e) > 0,
    );
    await open(tester, entry: lunch);
    await go(tester, ['退款']);
    expect(outcomes.single!.$1, ComposeOutcome.refund);
  });

  testWidgets('a refund is recorded against the spending it gives back', (
    tester,
  ) async {
    final bought = ledger.entries.all.firstWhere(
      (e) =>
          e.type == EntryType.expense &&
          ledger.entryQueryService.refundable(e) > 50,
    );
    final count = ledger.entries.length;
    await open(tester, refundOf: bought);
    expect(find.text('退款'), findsOneWidget);
    await amount(tester, '50', label: '退款金額');
    expect(find.text('記下退款'), findsOneWidget);
    await save(tester);
    final made = added(count).single;
    expect(
      (made.type, made.amount, made.refundOf),
      (EntryType.income, 50, bought.id),
    );
  });

  testWidgets('a draft given, such as a card payment, opens filled in', (
    tester,
  ) async {
    final count = ledger.entries.length;
    await open(
      tester,
      draft: Entry(
        id: '',
        date: ledger.today,
        type: EntryType.transfer,
        amount: 1500,
        account: 'bank',
        to: 'cash',
      ),
    );
    expect(find.text('確認轉帳'), findsOneWidget);
    await save(tester);
    final made = added(count).single;
    expect(
      (made.type, made.amount, made.account, made.to),
      (EntryType.transfer, 1500, 'bank', 'cash'),
    );
  });

  testWidgets('a spending paid partly for a friend is two entries, the '
      'friend\'s share owed', (tester) async {
    final count = ledger.entries.length;
    final owed = ledger.balanceService.balance('lent');
    await open(tester);
    await go(tester, ['代墊', '代墊朋友', '好了（1 人）']);
    await amount(tester, '500');
    // Shared evenly, one's own half counted as spending.
    expect(find.text('記下支出'), findsOneWidget);
    await save(tester);
    final made = added(count);
    expect(made, hasLength(2));
    expect(
      made.map((e) => e.type),
      containsAll([EntryType.expense, EntryType.transfer]),
    );
    expect(ledger.balanceService.balance('lent'), owed + 250);
  });

  testWidgets('money paid back by a friend is recorded against what they owe', (
    tester,
  ) async {
    final owed = ledger.balanceService.balance('lent');
    await open(tester);
    await go(tester, ['收入', '對方還錢']);
    expect(find.text('記下還款'), findsOneWidget);
    await save(tester);
    // It opens at all they owe.
    expect(ledger.balanceService.balance('lent'), 0);
    expect(owed, greaterThan(0));
  });
}
