import 'package:expense_tracker/src/core/design_system/password_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The eye beside a password shows what is typed, and hides it again;
/// words never hidden, such as a file path, have no eye.
void main() {
  Future<TextEditingController> field(
    WidgetTester tester, {
    bool hidden = true,
  }) async {
    final controller = TextEditingController(text: 'correct horse');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PasswordField(controller: controller, hint: '', hidden: hidden),
        ),
      ),
    );
    return controller;
  }

  bool obscured(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).obscureText;

  testWidgets('a password is hidden until the eye shows it', (tester) async {
    await field(tester);
    expect(obscured(tester), isTrue);
    await tester.tap(find.bySemanticsLabel('顯示密碼'));
    await tester.pump();
    expect(obscured(tester), isFalse);
    await tester.tap(find.bySemanticsLabel('隱藏密碼'));
    await tester.pump();
    expect(obscured(tester), isTrue);
  });

  testWidgets('words not hidden have no eye', (tester) async {
    await field(tester, hidden: false);
    expect(obscured(tester), isFalse);
    expect(find.bySemanticsLabel('顯示密碼'), findsNothing);
  });

  testWidgets('the keyboard learns nothing typed, hidden or not '
      '(review 22 finding 4)', (tester) async {
    for (final hidden in [true, false]) {
      await field(tester, hidden: hidden);
      final typed = tester.widget<TextField>(find.byType(TextField));
      expect(typed.enableIMEPersonalizedLearning, isFalse);
      expect(typed.keyboardType, TextInputType.visiblePassword);
      expect(typed.enableSuggestions, isFalse);
      expect(typed.autocorrect, isFalse);
    }
  });
}
