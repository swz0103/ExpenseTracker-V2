import 'package:ledger_entries/rules.dart';
import 'package:test/test.dart';

void main() {
  test('the rules entry point gathers every rule and issue', () {
    expect(maxInstallments, 60);
    expect(budgetIssues(limit: 1, warning: 80), isEmpty);
    expect(accountIssues(name: ' '), [isA<BlankName>()]);
    expect(recurringIssues(amount: 1, every: 1, day: 1), isEmpty);
    expect(const NegativeBalanceAfter(-1).severity, Severity.warning);
  });
}
