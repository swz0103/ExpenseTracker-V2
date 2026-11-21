import 'dart:async';

import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/overview/forms/overview_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

/// 調整總覽: hiding a block and showing it again, dragging one to another
/// place, and 恢復預設, each kept in the preferences at once.
void main() {
  setUpAll(loadFonts);

  late Preferences preferences;

  setUp(() => preferences = Preferences());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    unawaited(editOverview(context, preferences));
    await tester.pumpAndSettle();
  }

  /// The block labels in the order the editor lists them.
  List<String> listed(WidgetTester tester) => [
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
      (tile.title! as Text).data!,
  ];

  testWidgets('a block turned off is kept hidden, and on again shown', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('調整總覽'), findsOneWidget);
    expect(listed(tester), ['預算與即將扣款', '每日紀錄', '投資行情', '財務分布', '收支對照']);
    await go(tester, ['每日紀錄']);
    expect(preferences.overview, [
      'plan',
      '!daily',
      'market',
      'assets',
      'flow',
    ]);
    await go(tester, ['每日紀錄']);
    expect(preferences.overview, contains('daily'));
    expect(preferences.overview, isNot(contains('!daily')));
  });

  testWidgets('a block dragged by its handle takes its new place', (
    tester,
  ) async {
    await open(tester);
    final handles = find.byType(ReorderableDragStartListener);
    final rowHeight =
        tester.getCenter(handles.at(1)).dy - tester.getCenter(handles.at(0)).dy;
    final gesture = await tester.startGesture(tester.getCenter(handles.first));
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, rowHeight * 2.5 / 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    // Moved down past the rows it was dragged over, and kept so.
    final order = listed(tester);
    expect(order.indexOf('預算與即將扣款'), greaterThanOrEqualTo(2));
    expect(order.first, '每日紀錄');
    expect(preferences.overview, [
      for (final label in order)
        {
          '預算與即將扣款': 'plan',
          '每日紀錄': 'daily',
          '投資行情': 'market',
          '財務分布': 'assets',
          '收支對照': 'flow',
        }[label],
    ]);
  });

  testWidgets('恢復預設 puts every block back, shown, in the app\'s order', (
    tester,
  ) async {
    preferences.overviewSet(['flow', '!plan', 'daily']);
    await open(tester);
    expect(listed(tester).first, '收支對照');
    await go(tester, ['恢復預設']);
    expect(preferences.overview, isNull);
    expect(listed(tester), ['預算與即將扣款', '每日紀錄', '投資行情', '財務分布', '收支對照']);
  });
}
