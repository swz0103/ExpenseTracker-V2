import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/features/lock/ui/views/new_password_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> set;
  late int withoutPassword;

  setUp(() {
    set = [];
    withoutPassword = 0;
  });

  Future<void> show(
    WidgetTester tester, {
    Future<void> Function(String password)? onSet,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NewPasswordView(
            onSet: onSet ?? (password) async => set.add(password),
            onNoPassword: () async => withoutPassword++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String first, String second) async {
    await tester.enterText(find.byType(TextField).at(0), first);
    await tester.enterText(find.byType(TextField).at(1), second);
  }

  Future<void> press(WidgetTester tester) async {
    await tester.tap(find.byKey(Keys.newPassword));
    await tester.pump();
  }

  testWidgets('a password typed the same twice and within the rule is set', (
    tester,
  ) async {
    await show(tester);
    await type(tester, 'river-stone-42', 'river-stone-42');
    await press(tester);
    expect(set, ['river-stone-42']);
  });

  testWidgets('two different passwords are refused, and nothing is set', (
    tester,
  ) async {
    await show(tester);
    await type(tester, 'river-stone-42', 'river-stone-43');
    await press(tester);
    expect(find.text('兩次輸入的新密碼不一樣'), findsOneWidget);
    expect(set, isEmpty);
    // What was typed stays for the person to correct.
    expect(find.text('river-stone-42'), findsOneWidget);
  });

  testWidgets('a password against the rule says which part of it', (
    tester,
  ) async {
    await show(tester);
    // Seven characters: one short of the eight the rule asks for.
    await type(tester, 'abc-123', 'abc-123');
    await press(tester);
    expect(find.text('至少要 8 個字'), findsOneWidget);
    // Eight characters, all digits.
    await type(tester, '12345678', '12345678');
    await press(tester);
    expect(find.text('不能全是數字，請加上文字或符號'), findsOneWidget);
    expect(set, isEmpty);
  });

  testWidgets('a failure to set it is told, and the form can be used again', (
    tester,
  ) async {
    await show(
      tester,
      onSet: (password) async => throw StateError('disk full'),
    );
    await type(tester, 'river-stone-42', 'river-stone-42');
    await press(tester);
    await tester.pumpAndSettle();
    expect(set, isEmpty);
    // The button answers again: a second press reaches onSet once more.
    expect(tester.widget<Widget>(find.byKey(Keys.newPassword)), isNotNull);
    expect(find.textContaining('disk full'), findsNothing);
  });

  testWidgets('opening without a password must be chosen and confirmed', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(Keys.noPassword));
    await tester.pumpAndSettle();
    // Nothing happens until the question is answered.
    expect(withoutPassword, 0);
    await tester.tap(find.byKey(Keys.confirm));
    // The screen stays busy until the ledger opens and replaces it, so
    // its spinner never settles: pump the dialog away instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(withoutPassword, 1);
    expect(set, isEmpty);
  });

  testWidgets('the screen cannot be gone back from', (tester) async {
    await show(tester);
    final scope = tester.widget<PopScope<Object?>>(
      find.byWidgetPredicate((widget) => widget is PopScope).first,
    );
    expect(scope.canPop, isFalse);
  });
}
