import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart';
import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/vocabulary.dart';
import 'package:ledger_postings/rules/registry.dart';

/// A small book of today's kinds: a bank in NT$, one in US$, a card
/// closing on the 20th, two categories, a fee category and a stock.
const usdCode = CurrencyCode('USD');
final bank = moneyAccount('bank');
final usd = moneyAccount('usd');
final card = moneyAccount('card');
final food = categoryAccount('food');
final salary = categoryAccount('salary');
final fees = categoryAccount('fees');
final stock = holdingAccount('2330');

Day day(int m, int d, [int y = 2026]) => Day.of(BusinessDate(y, m, d));

AccountTree tree() => AccountTree([
  ...Fixed.all,
  LedgerAccount(
    id: bank,
    cls: AccountClass.asset,
    name: 'bank',
    owner: Owners.accounts,
    currency: homeCurrency,
    tag: 'bank',
  ),
  LedgerAccount(
    id: usd,
    cls: AccountClass.asset,
    name: 'usd',
    owner: Owners.accounts,
    currency: usdCode,
    tag: 'bank',
  ),
  LedgerAccount(
    id: card,
    cls: AccountClass.liability,
    name: 'card',
    owner: Owners.accounts,
    currency: homeCurrency,
    tag: 'card',
  ),
  LedgerAccount(
    id: pendingInstalments(card),
    cls: AccountClass.liability,
    name: 'card instalments',
    owner: Owners.cards,
    currency: homeCurrency,
    tag: Tags.pending,
    inNetWorth: false,
  ),
  for (final (id, cls) in [
    (food, AccountClass.expense),
    (fees, AccountClass.expense),
    (salary, AccountClass.income),
  ])
    LedgerAccount(
      id: id,
      cls: cls,
      name: id.value,
      owner: Owners.entries,
      tag: Tags.category,
    ),
  LedgerAccount(
    id: stock,
    cls: AccountClass.asset,
    name: '2330',
    owner: Owners.investments,
    currency: homeCurrency,
    commodity: '2330',
    tag: Tags.holding,
  ),
]);

/// The card's billing days: closing on the 20th, due on the 5th.
final cardSchedule = CardSchedule(closingDay: 20, dueDay: 5);

typedef Book = ({
  Journal journal,
  MemoryPostingStore store,
  BookReader reader,
  Map<IntentId, LedgerIntent> kept,
});

/// A journal of today's kinds over a memory store; [keep] writes an
/// intent and remembers it for the streams.
Book book() {
  final store = MemoryPostingStore();
  final kept = <IntentId, LedgerIntent>{};
  final accounts = tree();
  final journal = Journal(
    registry: todaysIntents(scheduleOf: (a) => a == card ? cardSchedule : null),
    accounts: accounts,
    store: store,
    source: (id) => kept[id],
  );
  return (
    journal: journal,
    store: store,
    reader: BookReader(store, accounts, Contributions(), homeCurrency),
    kept: kept,
  );
}

JournalResult keep(Book b, LedgerIntent intent) {
  final r = b.journal.put(intent);
  if (r is Written) b.kept[intent.id] = intent;
  return r;
}

/// Every posting of [id] as (account, amount, currency, day).
List<(String, int, String, int)> linesOf(Book b, String id) => [
  for (final p in b.store.postingsOfIntent(IntentId(id)))
    (p.account.value, p.amount, p.currency.value, p.date.ymd),
];
