import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/app/settings_page.dart';
import 'package:expense_tracker/src/app/shell.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:expense_tracker/src/core/platform/quick_action.dart';
import 'package:expense_tracker/src/app/platform_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app frame's part in the lock gate (work package 3.1): what back
/// does on the first screen, where a ledger reopened after a restore was
/// given up starts, and telling the gate where the person is.
void main() {
  Future<void> show(WidgetTester tester, PlatformServices services) async {
    tester.view.physicalSize = const Size(400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: AppShell(ledger: demoLedger(), services: services),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// What the framework asks the phone when the last route is popped.
  List<String> systemPops(WidgetTester tester) {
    final pops = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') pops.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return pops;
  }

  testWidgets('back on 總覽 puts the app behind and closes nothing (F67)', (
    tester,
  ) async {
    final pops = systemPops(tester);
    var left = 0;
    await show(tester, PlatformServices(leave: () async => left++));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(left, 1);
    expect(pops, isEmpty, reason: 'the app is not closed');
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('back from another tab goes to 總覽 first, and only then '
      'leaves', (tester) async {
    var left = 0;
    await show(tester, PlatformServices(leave: () async => left++));
    await tester.tap(find.byKey(Keys.tab('帳戶')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(left, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(left, 1);
  });

  testWidgets('where the app cannot be put behind, back on 總覽 closes it as '
      'before', (tester) async {
    final pops = systemPops(tester);
    await show(tester, const PlatformServices());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(pops, ['SystemNavigator.pop']);
  });

  testWidgets('a ledger reopened after a restore was given up starts on the '
      'page the person left from (F92)', (tester) async {
    final asked = <String>[];
    await show(
      tester,
      PlatformServices(
        takeReturn: () {
          asked.add('return');
          return const SettingsRoute(SettingsDestination.security);
        },
      ),
    );
    expect(asked, ['return'], reason: 'asked once, as it opens');
    final security = find.byWidgetPredicate(
      (w) => w is SettingsPage && w.part == SettingsDestination.security,
    );
    expect(security, findsOneWidget);
    // Back leads where it always does from there: to 設定.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(security, findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is SettingsPage && w.part == null),
      findsOneWidget,
    );
  });

  testWidgets('the gate is told the page shown over the tabs as it changes', (
    tester,
  ) async {
    final places = <AppRoute?>[];
    await show(tester, PlatformServices(onPlace: places.add));
    expect(places.last, isNull, reason: 'a tab, no page');
    await tester.tap(find.byKey(Keys.tab('更多')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Keys.tool('設定')));
    await tester.pumpAndSettle();
    expect(places.last, AppRoutes.settings);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(places.last, isNull);
  });

  testWidgets('an action handed over by the gate opens the composer once', (
    tester,
  ) async {
    final quick = ValueNotifier<QuickAction?>(QuickAction.expense);
    addTearDown(quick.dispose);
    await show(tester, PlatformServices(quick: quick));
    expect(find.byKey(Keys.save), findsOneWidget);
    expect(quick.value, isNull, reason: 'taken');
  });
}
