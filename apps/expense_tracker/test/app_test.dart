import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:expense_tracker/src/app.dart';
import 'package:expense_tracker/src/format.dart';
import 'package:expense_tracker/src/preview.dart';
import 'package:expense_tracker/src/problems.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

void main() {
  final clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 3, 4)));

  test('the preview seeds example accounts and entries', () async {
    final session = await previewSession(clock: clock);
    expect(session.accounts, hasLength(2));
    expect(formatMoney(session.netWorth.total), '55,295');
    expect(session.recent, hasLength(5));
    expect(formatMoney(session.monthTotal(2026, 10).expense), '205');
  });

  test('a recorded expense lowers the balance and notifies', () async {
    final session = await previewSession(clock: clock);
    var notified = 0;
    session.addListener(() => notified++);
    final cash = session.accounts.firstWhere((a) => a.name == '示範：現金');
    final amount = parseAmount(session.twd, '1,000');
    final submission = session.begin();
    Future<void> save() => session.record(
      submission,
      CashFlow.expense,
      cash,
      amount,
      session.today,
    );
    await save();
    expect(formatMoney(session.balanceOf(cash)), '2,295');
    expect(notified, 1);

    // A retry of the same submission replays it instead of booking twice.
    await save();
    expect(formatMoney(session.balanceOf(cash)), '2,295');
    expect(session.recent, hasLength(6));
  });

  test('undo keeps the entry in its own month', () async {
    final session = await previewSession(clock: clock);
    final cash = session.accounts.firstWhere((a) => a.name == '示範：現金');
    await session.record(
      session.begin(),
      CashFlow.expense,
      cash,
      Money(session.twd, BigInt.from(400)),
      BusinessDate(2026, 9, 20),
    );
    final entry = session.recent.firstWhere(
      (p) => p.date == BusinessDate(2026, 9, 20),
    );
    await session.reverse(session.begin(), entry);
    expect(formatMoney(session.monthTotal(2026, 9).expense), '0');
    expect(formatMoney(session.monthTotal(2026, 10).expense), '205');
  });

  test('a foreign account is left out of NT\$ totals and listed', () async {
    final session = await previewSession(clock: clock);
    final usd = Currency.of('USD');
    await session.openAccount(
      session.begin(),
      '美元帳戶',
      AccountKind.bank,
      opening: Money(usd, BigInt.from(10000)),
    );
    final worth = session.netWorth;
    expect(formatMoney(worth.total), '55,295');
    expect([for (final a in worth.unvalued) a.name], ['美元帳戶']);
  });

  test('refused input is explained in words', () {
    Object? error;
    try {
      parseAmount(Currency.of('TWD'), '1.5');
    } on MoneyException catch (e) {
      error = e;
    }
    expect(describeProblem(error!), '金額的小數位數太多。');
  });

  testWidgets('the shell starts', (tester) async {
    final seeded = await tester.runAsync(() => previewSession(clock: clock));
    final session = seeded!;
    await tester.pumpWidget(ExpenseApp(session: session));
    expect(find.text('記帳本 V2：介面重建中'), findsOneWidget);
  });
}
