import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart';
import 'package:domain/investments.dart' show HoldingStatus;
import 'package:expense_tracker/design_system/display/status.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/ledger/rules/advance_rules.dart';
import 'package:expense_tracker/src/core/ledger/rules/budget_rules.dart';
import 'package:expense_tracker/src/core/ledger/rules/recurring_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final due = BusinessDate(2026, 11, 20);

  test('a card bill has one wording per state', () {
    expect(cardBillLook(BillDue(due, 3)).words, '11/20 繳款 · 還有 3 天');
    expect(cardBillLook(BillDueToday(due)).words, '今天繳款');
    expect(cardBillLook(BillOverdue(due, 1)).words, '11/20 繳款 · 已逾期 1 天');
    expect(cardBillLook(const BillPaid()).words, '已繳清');
    expect(cardBillLook(const BillNotYetBilled()).words, '未出帳');
  });

  test('only due today and overdue ask for attention', () {
    expect(cardBillLook(BillDue(due, 3)).alerts, isFalse);
    expect(cardBillLook(BillDueToday(due)).alerts, isTrue);
    expect(cardBillLook(BillOverdue(due, 1)).alerts, isTrue);
    expect(cardBillLook(BillOverdue(due, 1)).color, AppColors.negative);
    expect(cardBillLook(const BillPaid()).alerts, isFalse);
  });

  test('a budget is 剩 what is left, or 超支 by how much', () {
    expect(budgetLead(const BudgetWithin(100)), '剩');
    expect(budgetLead(const BudgetNear(0)), '剩');
    expect(budgetLead(const BudgetOver(1)), '超支');
    expect(budgetFigure(const BudgetWithin(100)), 100);
    expect(budgetFigure(const BudgetOver(2345)), 2345);
    expect(budgetLook(const BudgetNear(5)).words, '快用完');
    expect(budgetLook(const BudgetOver(1)).words, '超支');
    expect(budgetLook(const BudgetOver(1)).id, 'over');
  });

  test('holdings, recurring periods and advances', () {
    expect(holdingLook(HoldingStatus.soldOut).words, '已賣光');
    expect(recurringLook(RecurringPeriodStatus.booked).words, '已入帳');
    expect(recurringLook(RecurringPeriodStatus.skipped).words, '已略過');
    expect(recurringLook(RecurringPeriodStatus.paused).words, '已暫停');
    expect(advanceLook(AdvanceStatus.open).words, '未收回');
    expect(advanceLook(AdvanceStatus.partlySettled).words, '部分收回');
    expect(advanceLook(AdvanceStatus.settled).words, '已結清');
  });

  test('a day all let go is 已略過, not 已入帳 (F84)', () {
    expect(settledDayWords([RecurringPeriodStatus.skipped]), '已略過');
    expect(settledDayWords([RecurringPeriodStatus.booked]), '已入帳');
    expect(
      settledDayWords([
        RecurringPeriodStatus.booked,
        RecurringPeriodStatus.skipped,
      ]),
      '已入帳 · 已略過',
    );
  });
}
