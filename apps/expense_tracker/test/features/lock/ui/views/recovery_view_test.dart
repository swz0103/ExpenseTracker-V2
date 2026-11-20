import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/features/lock/ui/views/recovery_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/places.dart';

void main() {
  late List<String> pressed;
  late TextEditingController code;

  setUp(() {
    pressed = [];
    code = TextEditingController();
  });
  tearDown(() => code.dispose());

  Future<void> show(
    WidgetTester tester, {
    bool busy = false,
    bool canGoBack = true,
    String? problem,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecoveryView(
            code: code,
            busy: busy,
            problem: problem,
            onSubmit: () => pressed.add('submit'),
            onPassword: () => pressed.add('password'),
            onBack: canGoBack ? () => pressed.add('back') : null,
          ),
        ),
      ),
    );
    // Busy turns a spinner, which never settles.
    busy ? await tester.pump() : await tester.pumpAndSettle();
  }

  testWidgets('the code is typed in the open, and 打開 opens with it', (
    tester,
  ) async {
    await show(tester);
    await tester.enterText(find.byType(TextField), 'ABCD-EFGH');
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    expect(code.text, 'ABCD-EFGH');
    await go(tester, ['打開']);
    expect(pressed, ['submit']);
  });

  testWidgets('Enter on the keyboard opens as 打開 does', (tester) async {
    await show(tester);
    await tester.enterText(find.byType(TextField), 'ABCD');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(pressed, ['submit']);
  });

  testWidgets('改用密碼 and back each say where to go', (tester) async {
    await show(tester);
    await go(tester, ['改用密碼']);
    await tester.tap(find.byKey(Keys.back));
    expect(pressed, ['password', 'back']);
  });

  testWidgets('with nowhere to go back to, there is no back', (tester) async {
    await show(tester, canGoBack: false);
    expect(find.byKey(Keys.back), findsNothing);
  });

  testWidgets('while it opens, nothing can be pressed twice', (tester) async {
    await show(tester, busy: true);
    final links = tester.widgetList<TextButton>(find.byType(TextButton));
    expect(links, hasLength(2));
    expect(links.every((b) => b.onPressed == null), isTrue);
  });

  testWidgets('a problem is shown under the field', (tester) async {
    await show(tester, problem: '救援碼不對');
    expect(find.text('救援碼不對'), findsOneWidget);
  });
}
