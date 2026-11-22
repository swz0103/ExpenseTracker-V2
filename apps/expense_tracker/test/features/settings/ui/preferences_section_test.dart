import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/settings/ui/preferences_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("券商手續費折扣 shows the discount and sets another", (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final preferences = Preferences();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: preferences,
              builder: (context, _) =>
                  AppearanceSection(preferences: preferences),
            ),
          ),
        ),
      ),
    );
    expect(find.text('券商手續費折扣'), findsOneWidget);
    expect(find.text('6 折'), findsOneWidget);
    await tester.tap(find.text('券商手續費折扣'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.8 折'));
    await tester.pumpAndSettle();
    expect(preferences.brokerDiscount, 2800);
  });
}
