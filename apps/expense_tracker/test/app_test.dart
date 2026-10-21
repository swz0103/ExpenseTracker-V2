import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/app.dart';
import 'package:expense_tracker/src/model/journal.dart';
import 'package:expense_tracker/src/problems.dart';
import 'package:flutter/material.dart'
    show
        ClampingScrollPhysics,
        GlowingOverscrollIndicator,
        ListView,
        ScrollConfiguration,
        StretchingOverscrollIndicator,
        Text;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('refused changes are explained in words', () {
    expect(
      describeProblem(const MoneyException(MoneyError.precision)),
      '金額的小數位數太多。',
    );
    expect(
      describeProblem(JournalFailure(StateError('closed'))),
      '帳本無法寫入，請重新打開 App 再試。',
    );
    expect(describeProblem(StateError('x')), '發生未預期的錯誤。');
  });

  testWidgets('the shell starts', (tester) async {
    await tester.pumpWidget(const ExpenseApp());
    expect(find.text('記帳本'), findsOneWidget);
  });

  testWidgets('lists stop at their ends without stretching', (tester) async {
    await tester.pumpWidget(
      ExpenseApp(
        home: ListView(children: [for (var i = 0; i < 3; i++) Text('$i')]),
      ),
    );
    final context = tester.element(find.byType(ListView));
    expect(
      ScrollConfiguration.of(context).getScrollPhysics(context),
      isA<ClampingScrollPhysics>(),
    );
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(find.byType(GlowingOverscrollIndicator), findsNothing);
  });
}
