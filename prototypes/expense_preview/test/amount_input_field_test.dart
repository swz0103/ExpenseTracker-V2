import 'package:expense_preview/amount_input_field.dart';
import 'package:expense_preview/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

void main() {
  testWidgets(
    'calculate does not mutate input; explicit apply notifies once and edits invalidate proposals',
    (tester) async {
      final controller = TextEditingController(text: '120+85-20');
      var changed = 0;
      Future<void> mount(Currency currency, {bool enabled = true}) =>
          tester.pumpWidget(
            MaterialApp(
              locale: const Locale("zh", "TW"),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: AmountInputField(
                    controller: controller,
                    label: '金額',
                    currency: currency,
                    enabled: enabled,
                    onChanged: () => changed++,
                  ),
                ),
              ),
            ),
          );
      try {
        await mount(Currency('TWD', 2));
        for (final oversized in ['1' * 129, '😀' * 65]) {
          await tester.enterText(find.byType(TextField), oversized);
          expect(controller.text, '120+85-20');
          expect(changed, 0);
        }
        await tester.tap(find.byTooltip('計算金額'));
        await tester.pump();
        expect(controller.text, '120+85-20');
        expect(changed, 0);
        expect(find.text('計算結果：TWD 185.00'), findsOneWidget);
        await tester.tap(find.text('套用結果'));
        await tester.pump();
        expect(controller.text, '185.00');
        expect(changed, 1);
        expect(find.byKey(const Key('calculation-result')), findsNothing);
        await tester.tap(find.byTooltip('計算金額'));
        await tester.pump();
        controller.text = '1+2';
        await tester.pump();
        expect(find.text('套用結果'), findsNothing);
        await tester.tap(find.byTooltip('計算金額'));
        await tester.pump();
        await mount(Currency('JPY', 0));
        expect(find.text('套用結果'), findsNothing);
        await tester.tap(find.byTooltip('計算金額'));
        await tester.pump();
        expect(find.text('計算結果：JPY 3'), findsOneWidget);
        await mount(Currency('JPY', 0), enabled: false);
        expect(find.text('套用結果'), findsNothing);
        expect(
          tester.widget<IconButton>(find.byType(IconButton)).onPressed,
          isNull,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
  testWidgets(
    'errors retain original text; rounding is visible and large text remains operable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale("zh", "TW"),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(3.2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: AmountInputField(
                    controller: controller,
                    label: '金額',
                    currency: Currency('USD', 2),
                    enabled: true,
                    onChanged: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        for (final text in ['1/0', '1+', '92233720368547758.08']) {
          controller.text = text;
          await tester.pump();
          await tester.ensureVisible(find.byTooltip('計算金額'));
          await tester.tap(find.byTooltip('計算金額'));
          await tester.pump();
          expect(find.byKey(const Key('calculation-error')), findsOneWidget);
          expect(find.text('套用結果'), findsNothing);
          expect(controller.text, text);
        }
        controller.text = '1/3';
        await tester.pump();
        await tester.tap(find.byTooltip('計算金額'));
        await tester.pump();
        expect(find.text('結果已依 USD 小數 2 位四捨五入。'), findsOneWidget);
        await tester.ensureVisible(find.text('套用結果'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await tester.tap(find.text('套用結果'));
        await tester.pump();
        expect(controller.text, '0.33');
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
}
