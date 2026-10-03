import 'package:app_core/app_core.dart';
import 'package:expense_tracker/src/app.dart';
import 'package:expense_tracker/src/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

void main() {
  AppSession session() => AppSession.preview(
    clock: FixedClock(UtcInstant(DateTime.utc(2026, 10, 3, 4))),
  );

  testWidgets('accounts show example balances', (tester) async {
    final preview = session();
    await tester.runAsync(() => preview.ready);
    await tester.pumpWidget(ExpenseApp(session: preview));
    await tester.pump();
    expect(find.text('示範：現金'), findsOneWidget);
    expect(find.text('3,295.00'), findsOneWidget);
    expect(find.text('NT\$ 55,295.00'), findsOneWidget);
  });

  testWidgets('recording an expense updates the balance', (tester) async {
    final preview = session();
    await tester.runAsync(() => preview.ready);
    await tester.pumpWidget(ExpenseApp(session: preview));
    await tester.pump();
    await tester.tap(find.text('記一筆'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('record-amount')), '1,000');
    await tester.tap(find.byKey(const Key('record-save')));
    await tester.pumpAndSettle();
    expect(find.text('2,295.00'), findsOneWidget);
    expect(find.text('NT\$ 54,295.00'), findsOneWidget);
  });

  testWidgets('a bad amount explains itself', (tester) async {
    final preview = session();
    await tester.runAsync(() => preview.ready);
    await tester.pumpWidget(ExpenseApp(session: preview));
    await tester.pump();
    await tester.tap(find.text('記一筆'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('record-amount')), '1.234');
    await tester.tap(find.byKey(const Key('record-save')));
    await tester.pumpAndSettle();
    expect(find.text('金額的小數位數太多。'), findsOneWidget);
  });
}
