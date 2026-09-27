import 'package:expense_preview/business_calendar.dart';
import 'package:expense_preview/business_date_input_field.dart';
import 'package:expense_preview/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    TextEditingController controller, {
    bool enabled = true,
    bool Function()? canApply,
    VoidCallback? onChanged,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BusinessDateInputField(
              controller: controller,
              label: '日期（YYYY-MM-DD）',
              help: '選擇記帳日期',
              enabled: enabled,
              canApply: canApply ?? () => true,
              onChanged: onChanged ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byTooltip('選擇日期'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  }

  Future<void> close(WidgetTester tester, String button) async {
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Traditional Chinese leap-day selection is explicit and notifies once',
    (tester) async {
      final controller = TextEditingController(text: '2024-02-28');
      var changes = 0;
      try {
        await mount(tester, controller, onChanged: () => changes++);
        await open(tester);
        final context = tester.element(find.byType(DatePickerDialog));
        expect(Localizations.localeOf(context), const Locale('zh', 'TW'));
        expect(MaterialLocalizations.of(context).cancelButtonLabel, '取消');
        expect(
          find.byType(TextField),
          findsOneWidget,
        ); // Only the underlying ISO field.
        await tester.tap(find.text('29').hitTestable());
        await tester.pumpAndSettle();
        expect(controller.text, '2024-02-28');
        expect(changes, 0);
        await close(tester, '確定');
        expect(controller.text, '2024-02-29');
        expect(changes, 1);
        await open(tester);
        await close(tester, '確定');
        expect(changes, 1); // An unchanged date is not another draft write.
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'partial or invalid text is not normalized on open or cancel; oversized edits rejected whole',
    (tester) async {
      final controller = TextEditingController();
      var changes = 0;
      try {
        await mount(tester, controller, onChanged: () => changes++);
        for (final text in [
          '',
          '2024-02-',
          '2023-02-29',
          '0000-01-01',
          '10000-01-01',
        ]) {
          controller.text = text;
          await tester.pump();
          await open(tester);
          expect(controller.text, text);
          await close(tester, '取消');
          expect(controller.text, text);
        }
        expect(changes, 0);
        controller.text = '2024-02-';
        for (final text in ['1' * 33, '😀' * 17]) {
          await tester.enterText(find.byType(TextField), text);
          expect(controller.text, '2024-02-');
        }
        expect(changes, 0);
        await tester.enterText(find.byType(TextField), '2024-02-29');
        expect(changes, 1);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'pending selection cannot overwrite edited text or a changed session before rebuild',
    (tester) async {
      final controller = TextEditingController(text: '2024-02-28');
      var changes = 0, session = 1;
      try {
        await mount(
          tester,
          controller,
          onChanged: () => changes++,
          canApply: () => session == 1,
        );
        await open(tester);
        await tester.tap(find.text('29').hitTestable());
        await tester.pumpAndSettle();
        controller.text = '2024-03-01';
        controller.text =
            '2024-02-28'; // Even an ABA edit invalidates pending selection.
        await close(tester, '確定');
        expect(controller.text, '2024-02-28');
        expect(changes, 0);
        await open(tester);
        await tester.tap(find.text('29').hitTestable());
        await tester.pumpAndSettle();
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '確定'))
            .onPressed!();
        session =
            2; // Lock before Future continuation, without a widget rebuild.
        await tester.pumpAndSettle();
        expect(controller.text, '2024-02-28');
        expect(changes, 0);
        await mount(tester, controller, enabled: false);
        expect(
          tester.widget<IconButton>(find.byType(IconButton)).onPressed,
          isNull,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'full civil range and large text remain operable on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      final semantics = tester.ensureSemantics();
      try {
        await mount(tester, controller, scale: 3.2);
        for (final text in ['0001-01-01', '9999-12-31', '2011-12-30']) {
          controller.text = text;
          await tester.pump();
          await open(tester);
          final calendar = tester.widget<CalendarDatePicker>(
            find.byType(CalendarDatePicker),
          );
          expect(calendar.initialDate!.isUtc, isTrue);
          expect(
            calendar.initialDate!.toIso8601String().substring(0, 10),
            text,
          );
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await close(tester, '確定');
          expect(controller.text, text);
        }
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  test(
    'calendar arithmetic carries civil components without timezone conversion',
    () {
      const calendar = BusinessCalendar();
      final samples = [
        calendar.dateOnly(DateTime(2024, 2, 29, 23, 30)),
        calendar.getDay(2011, 12, 30),
        calendar.addDaysToDate(DateTime.utc(2011, 12, 29), 1),
        calendar.addDaysToDate(DateTime.utc(2024, 2, 28), 1),
        calendar.addMonthsToMonthDate(DateTime.utc(2024, 1, 31), 1),
        calendar.getMonth(1, 1),
        calendar.getDay(9999, 12, 31),
      ];
      expect(samples.every((date) => date.isUtc), isTrue);
      expect(samples.map((date) => date.toIso8601String().substring(0, 10)), [
        '2024-02-29',
        '2011-12-30',
        '2011-12-30',
        '2024-02-29',
        '2024-02-01',
        '0001-01-01',
        '9999-12-31',
      ]);
    },
  );
}
