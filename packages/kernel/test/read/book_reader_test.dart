import 'package:core/foundation_values.dart' show Currency, Money;
import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

import '../support/book.dart';

const gains = AccountId('gains');
const salary = AccountId('salary');

void main() {
  late MemoryPostingStore store;
  late AccountTree accounts;
  late Contributions contributions;
  late BookReader reader;

  setUp(() {
    final b = book();
    store = b.store;
    accounts = b.journal.accounts
      ..put(
        const LedgerAccount(
          id: gains,
          cls: AccountClass.income,
          name: 'gains',
          owner: owner,
          inFlowReports: false,
        ),
      )
      ..put(
        const LedgerAccount(
          id: salary,
          cls: AccountClass.income,
          name: 'salary',
          owner: owner,
        ),
      );
    contributions = Contributions();
    reader = BookReader(store, accounts, contributions, twd);
    for (final m in [
      Move('pay', day(1, 5), 1, from: salary, to: bank, amount: 50000),
      Move('lunch', day(1, 6), 2, from: bank, to: food, amount: 120),
      Move('gain', day(1, 7), 3, from: gains, to: bank, amount: 300),
      Move(
        'fx',
        day(1, 8),
        4,
        from: bank,
        to: dollars,
        amount: 3210,
        amendments: const {'fx': 10000},
      ),
      Move(
        'usdfood',
        day(2, 1),
        5,
        from: dollars,
        to: food,
        amount: 500,
        currency: usd,
      ),
    ]) {
      expect(b.journal.put(m), isA<Written>());
    }
    expect(
      b.journal.put(Beans('beans', Day.stored(20260109), 6, 2000000, 800)),
      isA<Written>(),
    );
  });

  test('balances at a day, all at once, and as Money', () {
    // 50000 - 120 + 300 - 3210 = 46970.
    expect(reader.balance(bank), 46970);
    expect(reader.balance(bank, until: day(1, 6)), 49880);
    expect(reader.balance(dollars), 9500); // 10000 - 500 cents
    expect(reader.balance(trading, currency: usd), -10000);
    expect(
      reader.balanceMoney(dollars),
      Money(Currency.of('USD'), BigInt.from(9500)),
    );
    expect(reader.balances(until: day(1, 5)), {
      (salary, twd): (amount: -50000, quantity: 0),
      (bank, twd): (amount: 50000, quantity: 0),
    });
    expect(reader.quantity(jar), 2000000);
    expect(reader.quantity(jar, until: day(1, 8)), 0);
  });

  test('postings, legs and lots', () {
    expect([for (final p in reader.postings(food)) p.amount], [120, 500]);
    expect(
      [for (final p in reader.legs(const IntentId('lunch'))) p.account],
      [bank, food],
    );
    expect(reader.bySub(jar), [(sub: 'beans', quantity: 2000000, amount: 800)]);
    expect(reader.bySub(jar, currency: usd), isEmpty);
  });

  test('every currency comes to zero', () {
    expect(reader.trialBalance(), {twd: 0, usd: 0});
  });

  test('a period: flows counted by class and flag, foreign apart', () {
    final january = reader.month(day(1, 20));
    expect(january.income, {salary: 50000});
    expect(january.spending, {food: 120});
    expect((january.incomeTotal, january.spendingTotal), (50000, 120));
    expect(january.foreign, isEmpty);
    final february = reader.period(day(2, 1), day(2, 28));
    expect(february.foreign, [(food, usd, 500)]);
    expect(february.spendingTotal, 0);
  });

  test('net worth: valued by the first valuer that knows, else unvalued', () {
    final bare = reader.netWorth(day(12, 31));
    // bank 46970, the jar at its cost 800, the cash paid for it -800;
    // dollars has no rate.
    expect((bare.assets, bare.liabilities, bare.net), (46970, 0, 46970));
    expect(bare.unvalued, [dollars]);
    contributions.on(valuers)
      ..add(
        owner,
        (unit, amount, asOf) => unit == 'USD' ? amount * 32 ~/ 100 : null,
      )
      ..add(
        owner,
        (unit, amount, asOf) => unit == 'beans' ? amount ~/ 1000 : null,
      );
    final valued = reader.netWorth(day(12, 31));
    // dollars 9500 × 32 / 100 = 3040; the jar 2,000,000 / 1000 = 2000;
    // 46970 + 3040 + 2000 - 800 = 51210.
    expect(valued.values, {bank: 46970, dollars: 3040, jar: 2000, cash: -800});
    expect(valued.net, 51210);
    expect(reader.toHome('TWD', 5, day(1, 1)), 5);
    expect(reader.toHome('JPY', 5, day(1, 1)), isNull);
  });

  test('a liability counts against net worth; uncounted accounts do not', () {
    accounts
      ..put(
        const LedgerAccount(
          id: cash,
          cls: AccountClass.liability,
          name: 'card',
          owner: owner,
          currency: twd,
        ),
      )
      ..put(
        const LedgerAccount(
          id: jar,
          cls: AccountClass.asset,
          name: 'jar',
          owner: owner,
          currency: twd,
          inNetWorth: false,
        ),
      );
    final b = Journal(
      registry: registry(),
      accounts: accounts,
      store: store,
      source: (_) => null,
    );
    expect(
      b.put(Move('card', day(3, 1), 7, from: cash, to: food, amount: 100)),
      isA<Written>(),
    );
    final worth = reader.netWorth(day(12, 31));
    // the jar paid 800 from cash, the card 100 more: owed 900.
    expect((worth.assets, worth.liabilities), (46970, 900));
  });
}
