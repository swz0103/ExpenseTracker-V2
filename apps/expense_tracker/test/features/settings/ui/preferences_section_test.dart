import 'package:expense_tracker/src/core/design_system/design_system.dart';
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
    // The last card opens the choices: two rows, 2.8折 the middle of the
    // second.
    await tester.tap(find.byType(SettingCard).last);
    await tester.pumpAndSettle();
    expect(find.text('2.8 折'), findsOneWidget);
    final secondRow = find.byType(Segments).at(1);
    await tester.tap(
      find
          .descendant(of: secondRow, matching: find.byType(GestureDetector))
          .at(1),
    );
    await tester.pumpAndSettle();
    expect(preferences.brokerDiscount, 2800);
  });
}
