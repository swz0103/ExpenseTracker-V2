import 'package:ledger_entries/rules.dart';
import 'package:test/test.dart';

List<Type> _types(List<RecordIssue> issues) => [
  for (final i in issues) i.runtimeType,
];

void main() {
  group('recurring items (LOG-07)', () {
    List<Type> recurring({
      int amount = 390,
      int every = 1,
      int day = 15,
      DateTime? start,
      DateTime? end,
    }) => _types(
      recurringIssues(
        amount: amount,
        every: every,
        day: day,
        start: start,
        end: end,
      ),
    );

    test('a monthly item on the 15th is kept', () {
      expect(recurring(), isEmpty);
    });
    test('an amount of nothing is refused', () {
      expect(recurring(amount: 0), [MissingAmount]);
    });
    test('every 0 or fewer is refused, every 1 kept', () {
      expect(recurring(every: 0), [IntervalTooSmall]);
      expect(recurring(every: -3), [IntervalTooSmall]);
    });
    test('day 0 and day 32 are refused, 1 and 31 kept', () {
      expect(recurring(day: 0), [DayOutOfRange]);
      expect(recurring(day: 32), [DayOutOfRange]);
      expect(recurring(day: 1), isEmpty);
      expect(recurring(day: 31), isEmpty);
    });
    test('an end before the start is refused, the same day kept', () {
      final start = DateTime.utc(2026, 5, 1);
      expect(recurring(start: start, end: DateTime.utc(2026, 4, 30)), [
        EndsBeforeStart,
      ]);
      expect(recurring(start: start, end: start), isEmpty);
    });
    test('an amount above the most kept is refused (R12 F3)', () {
      // 99,999,999,999 is the most in any currency (US cents).
      expect(
        _types(recurringShapeIssues(amount: 100000000000, every: 1, day: 5)),
        [AmountTooLarge],
      );
      expect(
        recurringShapeIssues(amount: 99999999999, every: 1, day: 5),
        isEmpty,
      );
      expect(_types(recurringIssues(amount: 100000000000, every: 1, day: 5)), [
        AmountTooLarge,
      ]);
    });
    test('read back, an amount of nothing still reads; below it does not', () {
      expect(recurringShapeIssues(every: 1, day: 5), isEmpty);
      expect(_types(recurringShapeIssues(amount: -1, every: 0, day: 40)), [
        MissingAmount,
        IntervalTooSmall,
        DayOutOfRange,
      ]);
    });
  });

  group('accounts (LOG-11, F68)', () {
    test('a named card on the 25th, due the 10th, limit 80,000 is kept', () {
      expect(
        accountIssues(name: '信用卡', closingDay: 25, dueDay: 10, limit: 80000),
        isEmpty,
      );
    });
    test('a name of only spaces is refused', () {
      expect(_types(accountIssues(name: '  ')), [BlankName]);
    });
    test('no name given is not checked', () {
      expect(accountIssues(), isEmpty);
    });
    test('days outside 1 to 31 are refused', () {
      expect(_types(accountIssues(closingDay: 0)), [ClosingDayOutOfRange]);
      expect(_types(accountIssues(dueDay: 32)), [DueDayOutOfRange]);
      expect(accountIssues(closingDay: 31, dueDay: 1), isEmpty);
    });
    test('a credit limit below nothing is refused, nothing kept', () {
      expect(_types(accountIssues(limit: -1)), [NegativeCreditLimit]);
      expect(accountIssues(limit: 0), isEmpty);
    });
    test('a credit limit above the most kept is refused (R12 F3)', () {
      // 99,999,999,999 is the most in any currency (US cents).
      expect(_types(accountShapeIssues(limit: 100000000000)), [AmountTooLarge]);
      expect(accountShapeIssues(limit: 99999999999), isEmpty);
      expect(_types(accountShapeIssues(opening: -100000000000)), [
        AmountTooLarge,
      ]);
      expect(accountShapeIssues(opening: -99999999999), isEmpty);
    });
    test('read back, the name is not asked for', () {
      expect(accountShapeIssues(), isEmpty);
      expect(_types(accountShapeIssues(closingDay: 0)), [ClosingDayOutOfRange]);
    });
  });

  group('budgets', () {
    test('a limit of 0 warning at 80% is kept', () {
      expect(budgetIssues(limit: 0, warning: 80), isEmpty);
    });
    test('a limit below nothing is refused', () {
      expect(_types(budgetIssues(limit: -1, warning: 80)), [
        NegativeBudgetLimit,
      ]);
    });
    test('a limit above the most kept is refused (R12 F3)', () {
      expect(_types(budgetIssues(limit: 100000000000, warning: 80)), [
        AmountTooLarge,
      ]);
    });
    test('a warning share outside 1% to 100% is refused', () {
      expect(_types(budgetIssues(limit: 1, warning: 0)), [WarningOutOfRange]);
      expect(_types(budgetIssues(limit: 1, warning: 101)), [WarningOutOfRange]);
      expect(budgetIssues(limit: 1, warning: 1), isEmpty);
      expect(budgetIssues(limit: 1, warning: 100), isEmpty);
    });
  });
}
