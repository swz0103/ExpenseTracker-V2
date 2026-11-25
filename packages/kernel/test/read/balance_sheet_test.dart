import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

import '../support/book.dart';

const salary = AccountId('salary');
const money = OwnerId('money');
const jars = OwnerId('jars');

void main() {
  late Contributions contributions;
  late BookReader reader;

  setUp(() {
    final b = book();
    final accounts = b.journal.accounts
      ..put(
        const LedgerAccount(
          id: salary,
          cls: AccountClass.income,
          name: 'salary',
          owner: owner,
        ),
      );
    contributions = Contributions();
    reader = BookReader(b.store, accounts, contributions, twd);
    for (final m in [
      Move('pay', day(1, 5), 1, from: salary, to: bank, amount: 50000),
      Move('lunch', day(1, 6), 2, from: bank, to: food, amount: 120),
    ]) {
      expect(b.journal.put(m), isA<Written>());
    }
    expect(
      b.journal.put(Beans('beans', Day.stored(20260109), 3, 2000000, 800)),
      isA<Written>(),
    );
  });

  test('no claims: every account is on the unclaimed row', () {
    final sheet = reader.balanceSheet(day(12, 31));
    // bank 50000 - 120 = 49880; the jar at its cost 800; cash -800.
    expect(sheet.rows, isEmpty);
    expect(sheet.unclaimed.owner, isNull);
    expect(sheet.unclaimed.row, unclaimedRow);
    expect(sheet.unclaimed.worth, 49880);
    expect(sheet.unclaimed.accounts.toSet(), {bank, jar, cash});
    expect(sheet.net, 49880);
    expect(sheet.contested, isEmpty);
    expect(sheet.unvalued, isEmpty);
  });

  test('modules claim accounts, the reader values them, the rows add up to '
      'net worth, and an account claimed twice counts once', () {
    contributions.on(sheetClaims)
      ..add(money, SheetClaim(row: 'bank', claims: (a) => a.id == bank))
      ..add(jars, SheetClaim(row: 'jars', claims: (a) => a.commodity != null))
      ..add(jars, SheetClaim(row: 'greedy', claims: (a) => a.id == bank));
    final sheet = reader.balanceSheet(day(12, 31));
    expect(
      [for (final r in sheet.rows) (r.owner, r.row, r.worth)],
      [
        (money, 'bank', 49880),
        (jars, 'jars', 800),
        // bank is the first claim's: counted there, named as contested.
        (jars, 'greedy', 0),
      ],
    );
    expect(
      [for (final r in sheet.rows) r.accounts],
      [
        [bank],
        [jar],
        <AccountId>[],
      ],
    );
    expect(sheet.unclaimed.worth, -800);
    expect(sheet.unclaimed.accounts, [cash]);
    // 49880 + 800 + 0 - 800 = 49880, the net worth.
    expect(sheet.net, 49880);
    expect(sheet.contested, {
      bank: ['bank', 'greedy'],
    });
  });

  test('before the first record, every row is at nothing', () {
    contributions
        .on(sheetClaims)
        .add(money, SheetClaim(row: 'bank', claims: (a) => a.id == bank));
    final sheet = reader.balanceSheet(day(1, 1));
    expect([for (final r in sheet.rows) (r.row, r.worth)], [('bank', 0)]);
    expect(sheet.unclaimed.worth, 0);
    expect(sheet.net, 0);
  });
}
