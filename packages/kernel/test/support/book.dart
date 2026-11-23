import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:kernel/kernel.dart';

/// A small book for the journal's tests: two money accounts in NT$, one
/// in US$, a spending account, and a jar whose stream refuses to go
/// below zero.
const twd = CurrencyCode('TWD');
const usd = CurrencyCode('USD');
const owner = OwnerId('test');
const bank = AccountId('bank');
const cash = AccountId('cash');
const dollars = AccountId('dollars');
const food = AccountId('food');
const jar = AccountId('jar');
const trading = AccountId('trading');

Day day(int m, int d, [int y = 2026]) => Day.of(BusinessDate(y, m, d));

AccountTree tree() => AccountTree([
  const LedgerAccount(
    id: bank,
    cls: AccountClass.asset,
    name: 'bank',
    owner: owner,
    currency: twd,
  ),
  const LedgerAccount(
    id: cash,
    cls: AccountClass.asset,
    name: 'cash',
    owner: owner,
    currency: twd,
  ),
  const LedgerAccount(
    id: dollars,
    cls: AccountClass.asset,
    name: 'dollars',
    owner: owner,
    currency: usd,
  ),
  const LedgerAccount(
    id: food,
    cls: AccountClass.expense,
    name: 'food',
    owner: owner,
  ),
  const LedgerAccount(
    id: jar,
    cls: AccountClass.asset,
    name: 'jar',
    owner: owner,
    currency: twd,
    commodity: 'beans',
  ),
  const LedgerAccount(
    id: trading,
    cls: AccountClass.equity,
    name: 'trading',
    owner: owner,
  ),
]);

/// Money moved: [amount] of [currency] from [from] to [to].
final class Move extends LedgerIntent {
  Move(
    String id,
    Day date,
    int seq, {
    required this.from,
    required this.to,
    required this.amount,
    this.currency = twd,
    super.amendments,
  }) : super(id: IntentId(id), date: date, seq: seq);

  static const kind = IntentType('move');
  final AccountId from;
  final AccountId to;
  final int amount;
  final CurrencyCode currency;

  @override
  IntentType get type => kind;
}

/// Beans into ([count] > 0) or out of the jar for [amount], refused when
/// more come out than the jar holds before it: a rule that reads the
/// book, in the `jar` stream.
final class Beans extends LedgerIntent {
  Beans(String id, Day date, int seq, this.count, this.amount)
    : super(id: IntentId(id), date: date, seq: seq);

  static const kind = IntentType('beans');
  final int count;
  final int amount;

  @override
  IntentType get type => kind;
}

final class MoveRule implements PostingRule<Move> {
  const MoveRule();

  @override
  Iterable<String> streams(Move intent) => const [];

  @override
  Posted post(Move i, RuleContext context) {
    if (i.amount <= 0) return const Refused('badAmount');
    return Lines([
      Line(i.from, -i.amount, i.currency),
      Line(i.to, i.amount, i.currency),
    ]);
  }
}

final class BeansRule implements PostingRule<Beans> {
  const BeansRule();

  @override
  Iterable<String> streams(Beans intent) => const ['jar'];

  @override
  Posted post(Beans i, RuleContext context) {
    final held = context.before(jar).fold(0, (n, p) => n + p.quantity);
    if (held + i.count < 0) return const Refused('tooFew', 'jar');
    return Lines([
      Line(jar, i.amount, twd, quantity: i.count, sub: i.id.value),
      Line(cash, -i.amount, twd),
    ]);
  }
}

/// Restates a line in another currency than its account's through the
/// trading account, at the value kept under `fx` (or refuses without).
Posted convert(Amendment a) {
  final out = <Line>[];
  for (final line in a.lines) {
    final own = a.context.accounts[line.account]?.currency;
    if (own == null || own == line.currency) {
      out.add(line);
      continue;
    }
    final value = a.value;
    if (value is! int) return const Refused('fx.needed', 'fx');
    final sign = line.amount.sign;
    out
      ..add(line.restated(sign * value, own))
      ..add(Line(trading, line.amount, line.currency))
      ..add(Line(trading, -sign * value, own));
  }
  return Lines(out);
}

IntentRegistry registry({bool amendable = true}) => IntentRegistry()
  ..register<Move>(
    IntentSpec(
      type: Move.kind,
      owner: owner,
      rule: const MoveRule(),
      amendable: amendable,
      touches: (i) => [i.from, i.to],
    ),
  )
  ..register<Beans>(
    const IntentSpec(type: Beans.kind, owner: owner, rule: BeansRule()),
  )
  ..amend(const Amender(slot: 'fx', owner: owner, order: 10, amend: convert));

/// A journal over a memory store, finding intents in [kept].
({Journal journal, MemoryPostingStore store, Map<IntentId, LedgerIntent> kept})
book({IntentRegistry? with_}) {
  final store = MemoryPostingStore();
  final kept = <IntentId, LedgerIntent>{};
  final journal = Journal(
    registry: with_ ?? registry(),
    accounts: tree(),
    store: store,
    source: (id) => kept[id],
  );
  return (journal: journal, store: store, kept: kept);
}
