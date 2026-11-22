import 'package:ledger_entries/rules.dart';
import 'package:test/test.dart';

void main() {
  test('every issue refuses its record, but a warning', () {
    const errors = <RecordIssue>[
      MissingAmount(trade: false),
      SplitTotalMismatch(1),
      IntervalTooSmall(),
      BlankName(),
      CloseMoveRefused(),
      WarningOutOfRange(),
    ];
    for (final issue in errors) {
      expect(issue.severity, Severity.error, reason: '$issue');
      expect(issue.isError, isTrue);
    }
    expect(const NegativeBalanceAfter(-1).severity, Severity.warning);
  });

  test('an issue names itself, for a log or an error message', () {
    expect('${const DayOutOfRange()}', 'DayOutOfRange');
  });
}
