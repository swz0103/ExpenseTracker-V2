import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:kernel/kernel.dart';
import 'package:ledger_loans/feature/loans_module.dart';
import 'package:test/test.dart';

const twd = CurrencyCode('TWD');
const accounts = OwnerId('accounts');
const bank = AccountId('acct:bank');
const car = AccountId('acct:car');
const amy = AccountId('acct:amy');
const opening = AccountId('equity:opening');

LedgerAccount money(AccountId id, AccountClass cls, String tag) =>
    LedgerAccount(
      id: id,
      cls: cls,
      name: id.value,
      owner: accounts,
      currency: twd,
      tag: tag,
    );

void main() {
  test('the module claims the loans and the people for the balance sheet; '
      'the journal values them, and the rows add up to net worth', () {
    final day = Day.of(BusinessDate(2026, 3, 1));
    final store = MemoryPostingStore();
    final tree = AccountTree([
      money(bank, AccountClass.asset, 'bank'),
      money(car, AccountClass.liability, 'loan'),
      money(amy, AccountClass.asset, 'receivable'),
      const LedgerAccount(
        id: opening,
        cls: AccountClass.equity,
        name: 'opening',
        owner: accounts,
      ),
    ]);
    var line = 0;
    Posting p(AccountId account, int amount) => Posting(
      intent: const IntentId('open'),
      line: line++,
      account: account,
      amount: amount,
      currency: twd,
      date: day,
      seq: 1,
    );
    store.put(
      IntentRow(
        id: const IntentId('open'),
        type: const IntentType('o'),
        date: day,
        seq: 1,
      ),
      // The bank holds 50,000, 300,000 is owed on the car, Amy owes 1,200.
      [p(bank, 50000), p(car, -300000), p(amy, 1200), p(opening, 248800)],
    );
    final contributions = Contributions();
    LoansModule.install(contributions);
    final sheet = BookReader(store, tree, contributions, twd).balanceSheet(day);
    expect(
      [for (final r in sheet.rows) (r.owner, r.row, r.worth)],
      [
        (LoansModule.owner, 'loans.loans', -300000),
        (LoansModule.owner, 'loans.people', 1200),
      ],
    );
    expect(sheet.unclaimed.accounts, [bank]);
    // 50000 - 300000 + 1200 = -248800.
    expect(
      sheet.unclaimed.worth + sheet.rows[0].worth + sheet.rows[1].worth,
      -248800,
    );
    expect(sheet.net, -248800);
    expect(sheet.contested, isEmpty);
  });
}
