import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart';
import 'package:kernel/kernel.dart';
import 'package:ledger_postings/model/intents.dart';
import 'package:ledger_postings/model/vocabulary.dart';
import 'package:ledger_postings/rules/registry.dart';
import 'package:test/test.dart';

import '../support/book.dart';

Spending spend(
  String id,
  AccountId account,
  int amount, {
  Map<String, Object?> amendments = const {},
  int d = 14,
}) => Spending(
  id: IntentId(id),
  date: day(9, d),
  seq: 1,
  account: account,
  parts: [(food, amount)],
  amendments: amendments,
);

void main() {
  group('a foreign value', () {
    test('restates the category at home, the far side on trading', () {
      final b = book();
      expect(
        keep(
          b,
          spend('meal', usd, 2000, amendments: const {Slots.fx: Worth(650)}),
        ),
        isA<Written>(),
      );
      expect(linesOf(b, 'meal'), [
        ('acct:usd', -2000, 'USD', 20260914),
        ('cat:food', 650, 'TWD', 20260914),
        ('equity:trading', 2000, 'USD', 20260914),
        ('equity:trading', -650, 'TWD', 20260914),
      ]);
      expect(b.reader.month(day(9, 1)).spending, {food: 650});
    });

    test('is what a transfer across currencies received', () {
      final b = book();
      keep(
        b,
        Transfer(
          id: const IntentId('fx'),
          date: day(9, 8),
          seq: 1,
          from: bank,
          to: usd,
          amount: 3210,
          amendments: const {Slots.fx: Worth(10000)},
        ),
      );
      expect(b.reader.balance(usd), 10000);
      expect(b.reader.balance(bank), -3210);
      expect(b.reader.trialBalance(), {homeCurrency: 0, usdCode: 0});
    });

    test('is needed where a line is in another currency, and only there', () {
      RuleRejected refused(LedgerIntent i) =>
          book().journal.put(i) as RuleRejected;
      expect(refused(spend('a', usd, 1)).code, 'fx.needed');
      expect(
        refused(spend('b', bank, 1, amendments: const {Slots.fx: Worth(1)}))
            .code,
        'fx.unused',
      );
      expect(
        refused(spend('c', usd, 1, amendments: const {Slots.fx: Worth(0)}))
            .code,
        'fx.badAmount',
      );
      final bad = refused(
        spend('d', usd, 1, amendments: const {Slots.fx: 'x'}),
      );
      expect((bad.code, bad.detail), ('fx.badValue', 'fx'));
    });

    test('one value for a received amount and a fee is ambiguous; an old '
        "book's fee counts as the same number", () {
      Transfer t(ForeignValue v) => Transfer(
        id: const IntentId('t'),
        date: day(9, 1),
        seq: 1,
        from: usd,
        to: bank,
        amount: 1000,
        fee: 5,
        feeCategory: fees,
        amendments: {Slots.fx: v},
      );
      expect(
        (book().journal.put(t(const Worth(32000))) as RuleRejected).code,
        'fx.ambiguous',
      );
      final b = book();
      expect(keep(b, t(const ReceivedFeeSameNumber(32000))), isA<Written>());
      expect(linesOf(b, 't'), [
        ('acct:usd', -1005, 'USD', 20260901), // 1000 + 5
        ('acct:bank', 32000, 'TWD', 20260901),
        ('cat:fees', 5, 'TWD', 20260901),
        ('equity:trading', 1000, 'USD', 20260901),
        ('equity:trading', -32000, 'TWD', 20260901),
        ('equity:trading', 5, 'USD', 20260901),
        ('equity:trading', -5, 'TWD', 20260901),
      ]);
      expect(
        (book().journal.put(
          t(const ReceivedFeeSameNumber(0)),
        ) as RuleRejected).code,
        'fx.badAmount',
      );
      final noMoney = book().journal.put(
        spend(
          's',
          usd,
          1,
          amendments: const {Slots.fx: ReceivedFeeSameNumber(3)},
        ),
      );
      expect((noMoney as RuleRejected).code, 'fx.unused');
    });

    test("an old book's foreign amount kept as the same number", () {
      final b = book();
      keep(
        b,
        spend('old', usd, 2000, amendments: const {Slots.fx: SameNumber()}),
      );
      // Today the 2,000 cents count as NT$2,000.
      expect(b.reader.month(day(9, 1)).spending, {food: 2000});
      expect(b.reader.balance(usd), -2000);
    });
  });

  group('instalments', () {
    test('the spending is whole on its day; the card owes as each '
        'statement closes', () {
      final b = book();
      keep(
        b,
        spend('tv', card, 10001, amendments: const {Slots.instalments: 3}),
      );
      // 10001 = 3335 + 3333 + 3333, billed on the 20ths.
      expect(linesOf(b, 'tv'), [
        ('cat:food', 10001, 'TWD', 20260914),
        ('acct:card:instalments', -10001, 'TWD', 20260914),
        ('acct:card:instalments', 3335, 'TWD', 20260920),
        ('acct:card', -3335, 'TWD', 20260920),
        ('acct:card:instalments', 3333, 'TWD', 20261020),
        ('acct:card', -3333, 'TWD', 20261020),
        ('acct:card:instalments', 3333, 'TWD', 20261120),
        ('acct:card', -3333, 'TWD', 20261120),
      ]);
      expect(b.reader.balance(card, until: day(9, 19)), 0);
      expect(b.reader.balance(card, until: day(10, 20)), -6668);
      expect(b.store.intent(const IntentId('tv'))!.streams, [
        'instalments:acct:card',
      ]);
    });

    test('a new schedule posts the purchases again', () {
      var schedule = CardSchedule(closingDay: 20, dueDay: 5);
      final store = MemoryPostingStore();
      final kept = <IntentId, LedgerIntent>{};
      final j = Journal(
        registry: todaysIntents(scheduleOf: (a) => a == card ? schedule : null),
        accounts: tree(),
        store: store,
        source: (id) => kept[id],
      );
      final tv = spend(
        'tv',
        card,
        900,
        amendments: const {Slots.instalments: 3},
      );
      kept[tv.id] = tv;
      expect(j.put(tv), isA<Written>());
      schedule = CardSchedule(
        closingDay: 10,
        dueDay: 25,
        history: [
          CardScheduleChange(
            until: BusinessDate(2026, 9, 10),
            closingDay: 20,
            dueDay: 5,
          ),
        ],
      );
      expect(j.rematerialise(Streams.instalments(card)), isA<Written>());
      // Bought on 9/14, closing on the 10th from now on.
      expect(
        [for (final p in store.postingsOf(card)) p.date.ymd],
        [20261010, 20261110, 20261210],
      );
    });

    test('refused without a count, a schedule, or one account to spread', () {
      RuleRejected refused(LedgerIntent i) =>
          book().journal.put(i) as RuleRejected;
      final one = refused(
        spend('a', card, 9, amendments: const {Slots.instalments: 1}),
      );
      expect((one.code, one.detail), ('instalments.count', 'instalments'));
      expect(
        refused(spend('b', card, 9, amendments: const {Slots.instalments: 'x'}))
            .code,
        'instalments.count',
      );
      expect(
        refused(spend('c', bank, 9, amendments: const {Slots.instalments: 3}))
            .code,
        'instalments.noSchedule',
      );
      expect(
        refused(
          Earning(
            id: const IntentId('e'),
            date: day(9, 1),
            seq: 1,
            account: card,
            category: salary,
            amount: 9,
            amendments: const {Slots.instalments: 3},
          ),
        ).code,
        'instalments.notOneAccount',
      );
    });
  });
}
