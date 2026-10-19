import 'package:core/app_core.dart';
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
      describeProblem(
        const AppFailure(FailureKind.rejected, 'app.card-transfer'),
      ),
      '信用卡不能轉出，請記成支出。',
    );
    expect(
      describeProblem(const MoneyException(MoneyError.precision)),
      '金額的小數位數太多。',
    );
    expect(
      describeProblem(const AppFailure(FailureKind.rejected, 'some.code')),
      '無法完成（some.code）。',
    );
    expect(
      describeProblem(
        const PartlyKept(2, 5, AppFailure(FailureKind.rejected, 'x.y')),
      ),
      '第 3 筆無法記下：無法完成（x.y）。前 2 筆已記下，其餘 2 筆沒有記。',
    );
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
