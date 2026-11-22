// Work package 1.4: what the ledger refuses is enforced where it writes.
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../baseline/baseline_ledger.dart';
import 'known_defect.dart';

Ledger book() => ledgerOf(
  today: day(2026, 10, 4),
  accounts: const [
    Account('bank', '銀行', AccountKind.bank, 1000),
    Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
  ],
);

void main() {
  final invalid = {
    'a zero amount': entryOf(
      'a',
      day(2026, 10, 4),
      EntryType.expense,
      0,
      'bank',
    ),
    'a transfer to the same account': entryOf(
      'b',
      day(2026, 10, 4),
      EntryType.transfer,
      100,
      'bank',
      to: 'bank',
    ),
    'foreign spending with no NT\$ amount': entryOf(
      'c',
      day(2026, 10, 4),
      EntryType.expense,
      100,
      'usd',
    ),
  };

  for (final MapEntry(:key, :value) in invalid.entries) {
    test('LOG-02: the ledger does not store $key, whoever writes it', () {
      final ledger = book();
      // The validator refuses it ...
      expect(ledger.entryValidator.validate(value), isNotNull);
      // ... so the write refuses it too, however it reports that.
      try {
        ledger.entryCommands.add(value);
      } on Object {
        // Refusing by throwing is one way to say no.
      }
      expect(ledger.entries.all, isEmpty);
    }, skip: knownDefect('LOG-02', '1.4'));
  }
}
