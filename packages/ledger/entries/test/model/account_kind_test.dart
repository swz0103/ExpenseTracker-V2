import 'package:ledger_entries/model.dart';
import 'package:test/test.dart';

void main() {
  test('cards and loans are owed; the rest is held', () {
    expect(
      [
        for (final k in AccountKind.values)
          if (k.isDebt) k,
      ],
      [AccountKind.card, AccountKind.loan],
    );
  });

  test('an account in another currency than NT\$ is foreign', () {
    expect(const AccountFacts(AccountKind.bank).foreign, isFalse);
    expect(
      const AccountFacts(AccountKind.bank, currency: 'USD').foreign,
      isTrue,
    );
  });
}
