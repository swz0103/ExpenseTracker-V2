import 'package:expense_tracker/src/core/design_system/spacing.dart';
import 'package:expense_tracker/src/features/lock/ui/views/unlock_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/android_text_scale.dart';
import '../../../../support/places.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);

  final password = TextEditingController();
  tearDownAll(password.dispose);

  Widget view({double? scale, String? problem, String? waiting}) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: scale == null
            ? TextScaler.noScaling
            : const AndroidTextScaler200(),
      ),
      child: child!,
    ),
    home: UnlockView(
      password: password,
      busy: false,
      problem: problem,
      waiting: waiting,
      onSubmit: () {},
      onRecovery: () {},
    ),
  );

  Future<void> show(
    WidgetTester tester,
    Widget page, {
    double width = 400,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(page);
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('a screen reader finds the password field, labelled', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await show(tester, view());
    final node = tester.getSemantics(find.bySemanticsLabel('帳本密碼'));
    expect(node.flagsCollection.isTextField, isTrue);
    expect(node.flagsCollection.isObscured, isTrue);
    handle.dispose();
  });

  testWidgets('the keyboard learns nothing typed (review 22 finding 4)', (
    tester,
  ) async {
    await show(tester, view());
    final typed = tester.widget<TextField>(find.byType(TextField));
    expect(typed.enableIMEPersonalizedLearning, isFalse);
    expect(typed.keyboardType, TextInputType.visiblePassword);
    expect(typed.enableSuggestions, isFalse);
    expect(typed.autocorrect, isFalse);
  });

  testWidgets('the name is read once', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester, view());
    expect(find.bySemanticsLabel('記帳本'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('忘記密碼？ is at least 48 dp high and every target is named', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await show(tester, view());
    final forgot = tester.getSize(find.widgetWithText(TextButton, '忘記密碼？'));
    expect(forgot.height, greaterThanOrEqualTo(Space.target));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('a wait is said once when it begins, not each second, and its '
      'end is said', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester, view());
    await tester.pumpWidget(view(waiting: '請等 30 秒再試'));
    await tester.pump();
    expect(find.bySemanticsLabel('請等 30 秒再試'), findsOneWidget);
    // The countdown moves on: what is read out stays what it was.
    await tester.pumpWidget(view(waiting: '請等 29 秒再試'));
    await tester.pump();
    expect(find.bySemanticsLabel('請等 30 秒再試'), findsOneWidget);
    expect(find.bySemanticsLabel('請等 29 秒再試'), findsNothing);
    // It ends.
    await tester.pumpWidget(view());
    await tester.pump();
    expect(find.bySemanticsLabel('可以再輸入密碼了'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a wrong password is announced as a live region', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester, view());
    await tester.pumpWidget(view(problem: '密碼不正確'));
    await tester.pump();
    final node = tester.getSemantics(find.bySemanticsLabel('密碼不正確'));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('at ${width.toInt()} dp a full row of dots, doubled text and '
        'a long problem fit', (tester) async {
      password.text = 'x' * 20;
      addTearDown(password.clear);
      await show(
        tester,
        view(scale: 2.0, problem: '輸入錯誤太多次，請等 4 分 30 秒再試，這是一行很長的說明文字'),
        width: width,
      );
      expect(tester.takeException(), isNull);
    });
  }

  /// The password's dots, in order: true for a filled one, false for a
  /// hollow one.
  List<bool> dots(WidgetTester tester) => [
    for (final c in tester.widgetList<Container>(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints ==
                const BoxConstraints.tightFor(width: 11, height: 11),
      ),
    ))
      (c.decoration! as BoxDecoration).color != null,
  ];

  testWidgets('nothing typed shows a single hollow dot, not a row (3.2-4)', (
    tester,
  ) async {
    password.clear();
    await show(tester, view());
    expect(dots(tester), [false]);
    // Three letters typed: three filled, then one hollow for the next.
    password.text = 'abc';
    addTearDown(password.clear);
    await tester.pump();
    expect(dots(tester), [true, true, true, false]);
  });
}
