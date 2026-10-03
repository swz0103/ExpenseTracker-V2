import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:expense_tracker/src/app.dart';
import 'package:expense_tracker/src/format.dart';
import 'package:expense_tracker/src/problems.dart';
import 'package:expense_tracker/src/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

void main() {
  final clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 3, 4)));

  test('the preview seeds example accounts and entries', () async {
    final session = AppSession.preview(clock: clock);
    await session.ready;
    expect(session.accounts, hasLength(2));
    expect(formatMoney(session.netWorth), '55,295.00');
    expect(session.recent, hasLength(5));
    expect(formatMoney(session.monthTotal(2026, 10).expense), '205.00');
  });

  test('a recorded expense lowers the balance and notifies', () async {
    final session = AppSession.preview(clock: clock);
    await session.ready;
    var notified = 0;
    session.addListener(() => notified++);
    final cash = session.accounts.firstWhere((a) => a.name == '示範：現金');
    final amount = parseAmount(session.twd, '1,000');
    await session.record(CashFlow.expense, cash, amount, session.today);
    expect(formatMoney(session.balanceOf(cash)), '2,295.00');
    expect(notified, 1);
  });

  test('refused input is explained in words', () {
    Object? error;
    try {
      parseAmount(Currency.iso('TWD'), '1.234');
    } on MoneyException catch (e) {
      error = e;
    }
    expect(describeProblem(error!), '金額的小數位數太多。');
  });

  testWidgets('the shell starts', (tester) async {
    final session = AppSession.preview(clock: clock);
    await tester.runAsync(() => session.ready);
    await tester.pumpWidget(ExpenseApp(session: session));
    expect(find.text('記帳本 V2：介面重建中'), findsOneWidget);
  });
}
