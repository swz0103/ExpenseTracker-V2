/// Checks 多久一次 and 其他設定 of a recurring item: the unit, the day,
/// weekday or day of the year, and how many units apart are kept; so are
/// an end, booking by itself when due, and a pause.
library;

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/recurring/forms/recurring_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

void main() {
  late Ledger ledger;
  late Recurring netflix;
  setUp(() {
    ledger = demoLedger();
    netflix = ledger.recurring.all.firstWhere((r) => r.name == 'Netflix');
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editRecurring(
                context,
                ledger,
                item: ledger.recurring.byId(netflix.id),
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

  Recurring kept() => ledger.recurring.byId(netflix.id)!;

  testWidgets('a weekly item is kept on the weekday picked, weeks apart', (
    tester,
  ) async {
    await open(tester);
    await go(tester, ['重複', '每週', '三', '~多一', '~多一', '~少一']);
    expect(find.textContaining('接下來：'), findsOneWidget);
    await go(tester, ['完成']);
    expect(find.bySemanticsLabel(RegExp('^重複')), findsOneWidget);
    await go(tester, ['儲存']);
    final item = kept();
    expect((item.unit, item.every), (RepeatUnit.week, 2));
    expect(item.start!.weekday, DateTime.wednesday);
  });

  testWidgets('a yearly item is kept on the month and day picked', (
    tester,
  ) async {
    await open(tester);
    await go(tester, ['重複', '每年', '3', '15', '完成', '儲存']);
    final item = kept();
    expect(item.unit, RepeatUnit.year);
    expect((item.start!.month, item.start!.day), (3, 15));
  });

  testWidgets('a day of the month a short month lacks falls on its last', (
    tester,
  ) async {
    await open(tester);
    await go(tester, ['重複', '每年', '31', '2', '完成', '儲存']);
    final start = kept().start!;
    expect((start.month, start.day), (2, DateTime.utc(start.year, 3, 0).day));
  });

  testWidgets('R26: February picked after its day in a leap year moves to '
      'the next February, on its last day', (tester) async {
    ledger = demoLedger(today: DateTime.utc(2028, 10, 4));
    netflix = ledger.recurring.all.firstWhere((r) => r.name == 'Netflix');
    await open(tester);
    // 31 of a month in 2028, then February: 29 Feb 2028 is before the
    // start, so the next February, 2029, which has 28 days.
    await go(tester, ['重複', '每年', '31', '2', '完成', '儲存']);
    expect(kept().start, DateTime.utc(2029, 2, 28));
  });

  testWidgets('a monthly item is kept on the day picked; a daily one on none', (
    tester,
  ) async {
    await open(tester);
    await go(tester, ['重複', '20', '完成', '儲存']);
    expect((kept().unit, kept().start!.day), (RepeatUnit.month, 20));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await go(tester, ['重複', '每天', '~多一', '完成', '儲存']);
    expect((kept().unit, kept().every), (RepeatUnit.day, 2));
  });

  testWidgets('booking by itself and a pause are kept from 其他設定', (
    tester,
  ) async {
    final auto = netflix.auto;
    await open(tester);
    await go(tester, ['其他設定', '到期自動入帳', '暫停']);
    await go(tester, ['完成', '儲存']);
    expect(kept().auto, !auto);
    expect(kept().active, isFalse);
  });

  testWidgets('an end is set from 其他設定, and taken away again', (tester) async {
    await open(tester);
    // The month shown is the start's, October.
    await go(tester, ['其他設定', '結束', '28']);
    expect(find.bySemanticsLabel(RegExp('^結束 10/28')), findsOneWidget);
    await go(tester, ['完成', '儲存']);
    expect(kept().end, DateTime.utc(2026, 10, 28));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await go(tester, ['其他設定', '~不結束', '完成', '儲存']);
    expect(kept().end, isNull);
  });
}
