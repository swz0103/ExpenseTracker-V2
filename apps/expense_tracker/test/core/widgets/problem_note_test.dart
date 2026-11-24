/// Checks that a refused change is told at the foot of the screen in
/// words a person can act on, and that the note goes by itself.
library;

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/widgets/problem_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> refuse(WidgetTester tester, Object error) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProblem(context, error),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a sale that would leave too few shares is told so', (
    tester,
  ) async {
    await refuse(
      tester,
      RecordRefused([const SaleExceedsHolding(later: true)]),
    );
    expect(find.text('這樣之後的賣出或減資會超過持股，請先改那一筆'), findsOneWidget);
  });

  testWidgets('a change that could not be kept asks to open the app again', (
    tester,
  ) async {
    await refuse(tester, KeepFailed(Exception('disk full')));
    expect(find.text('帳本無法寫入，請重新打開 App 再試。'), findsOneWidget);
  });

  testWidgets('an error nobody foresaw still says something', (tester) async {
    await refuse(tester, StateError('?'));
    expect(find.text('發生未預期的錯誤。'), findsOneWidget);
  });

  testWidgets('the note goes by itself after a while', (tester) async {
    await refuse(tester, const NameTaken());
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a button whose change is refused says why, not nothing', (
    tester,
  ) async {
    bool? done;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => done = refusalShown(
                context,
                () => throw RecordRefused(const [BlankName()]),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(done, isFalse);
    expect(find.text('請輸入帳戶名稱'), findsOneWidget);
  });
}
