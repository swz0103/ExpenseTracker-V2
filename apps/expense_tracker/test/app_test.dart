import 'package:app_core/app_core.dart';
import 'package:expense_tracker/src/app.dart';
import 'package:expense_tracker/src/problems.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

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
  });

  testWidgets('the shell starts', (tester) async {
    await tester.pumpWidget(const ExpenseApp());
    expect(find.text('記帳本 V2：介面重建中'), findsOneWidget);
  });
}
