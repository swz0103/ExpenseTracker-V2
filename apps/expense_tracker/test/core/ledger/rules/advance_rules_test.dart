import 'package:expense_tracker/src/core/ledger/rules/advance_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('advanceStatus', () {
    test('nothing back is open', () {
      expect(advanceStatus(amount: 500, left: 500), AdvanceStatus.open);
    });

    test('some back is partly settled', () {
      // 500 lent, 499 still owed: 1 came back.
      expect(
        advanceStatus(amount: 500, left: 499),
        AdvanceStatus.partlySettled,
      );
    });

    test('all back is settled', () {
      expect(advanceStatus(amount: 500, left: 0), AdvanceStatus.settled);
    });
  });
}
