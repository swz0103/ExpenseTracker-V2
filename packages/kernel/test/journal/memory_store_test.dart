import 'dart:math';

import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

import '../support/book.dart';

Posting p(
  String intent,
  int line,
  AccountId a,
  int amount,
  Day d,
  int seq, {
  int quantity = 0,
  String sub = '',
}) => Posting(
  intent: IntentId(intent),
  line: line,
  account: a,
  amount: amount,
  currency: twd,
  date: d,
  seq: seq,
  quantity: quantity,
  sub: sub,
);

IntentRow row(String id, Day d, int seq, [List<String> streams = const []]) =>
    IntentRow(
      id: IntentId(id),
      type: const IntentType('t'),
      date: d,
      seq: seq,
      streams: streams,
    );

/// The sums of [postings] in a plain pass, for comparison.
AccountSums scan(List<Posting> postings, int lo, int hi) {
  final out = <(AccountId, CurrencyCode), AccountSum>{};
  for (final x in postings) {
    if (x.date.ymd < lo || x.date.ymd > hi) continue;
    final k = (x.account, x.currency);
    out[k] = addSums(out[k] ?? (amount: 0, quantity: 0), (
      amount: x.amount,
      quantity: x.quantity,
    ));
  }
  return out..removeWhere((_, s) => s.amount == 0 && s.quantity == 0);
}

void main() {
  test('sums by month agree with a plain pass over every posting', () {
    final r = Random(7);
    final store = MemoryPostingStore();
    final all = <String, List<Posting>>{};
    for (var i = 0; i < 400; i++) {
      final d = Day.stored(
        20250000 + (1 + r.nextInt(12)) * 100 + 1 + r.nextInt(28),
      );
      final amount = r.nextInt(1000) + 1;
      final id = 'i${r.nextInt(150)}'; // some written over
      final ps = [
        p(id, 0, bank, -amount, d, i),
        p(id, 1, food, amount, d, i, quantity: r.nextInt(3)),
      ];
      store.put(row(id, d, i), ps);
      all[id] = ps;
    }
    for (var k = 0; k < 20; k++) {
      store.remove(IntentId("i${r.nextInt(150)}"));
    }
    final kept = [
      for (final MapEntry(:key, :value) in all.entries)
        if (store.intent(IntentId(key)) != null) ...value,
    ];
    for (final (lo, hi) in [
      (0, 99991231),
      (20250301, 20250331),
      (20250215, 20250710),
      (20250101, 20250101),
      (0, 20250614),
    ]) {
      expect(
        store.sums(
          from: lo == 0 ? null : Day.stored(lo),
          until: Day.stored(hi),
        ),
        scan(kept, lo, hi),
        reason: '$lo..$hi',
      );
    }
    expect(store.postingCount, kept.length);
  });

  test('a transaction that throws leaves everything as it was', () {
    final store = MemoryPostingStore();
    store.put(row('a', day(1, 1), 1), [
      p('a', 0, bank, 5, day(1, 1), 1),
      p('a', 1, food, -5, day(1, 1), 1),
    ]);
    store.keepAccounts(tree().all);
    expect(
      () => store.transaction(() {
        store.remove(const IntentId('a'));
        store.put(row('b', day(1, 2), 2), [p('b', 0, bank, 9, day(1, 2), 2)]);
        store.keepAccounts(const []);
        throw StateError('no');
      }),
      throwsStateError,
    );
    expect(store.sums(), {
      (bank, twd): (amount: 5, quantity: 0),
      (food, twd): (amount: -5, quantity: 0),
    });
    expect(store.intent(const IntentId('b')), isNull);
    expect(store.accounts().length, 6);
    expect(
      () => store.transaction(() => store.transaction(() => 1)),
      throwsStateError,
    );
  });

  test('streams, postings in book order and before a place', () {
    final store = MemoryPostingStore();
    store.put(row('late', day(1, 3), 1, ['s']), [
      p('late', 0, jar, 3, day(1, 3), 1),
    ]);
    store.put(row('early', day(1, 1), 9, ['s']), [
      p('early', 0, jar, 1, day(1, 1), 9),
    ]);
    store.put(row('mid', day(1, 3), 0, ['s', 't']), [
      p('mid', 0, jar, 2, day(1, 3), 0),
    ]);
    expect(
      [
        for (final r in store.inStream('s', from: (date: day(1, 2), seq: 0)))
          r.id.value,
      ],
      ['mid', 'late'],
    );
    expect([for (final x in store.postingsOf(jar)) x.amount], [1, 2, 3]);
    expect(
      [
        for (final x in store.postingsOf(
          jar,
          before: (date: day(1, 3), seq: 1),
        ))
          x.amount,
      ],
      [1, 2],
    );
    expect(store.inStream('none', from: (date: day(1, 1), seq: 0)), isEmpty);
    expect(store.postingsOfIntent(const IntentId('none')), isEmpty);
  });

  test('sums by sub key, and clear keeps only the accounts', () {
    final store = MemoryPostingStore()..keepAccounts(tree().all);
    store.put(row('b1', day(1, 1), 1), [
      p('b1', 0, jar, 100, day(1, 1), 1, quantity: 10, sub: 'b1'),
    ]);
    store.put(row('b2', day(2, 1), 2), [
      p('b2', 0, jar, 50, day(2, 1), 2, quantity: 4, sub: 'b2'),
    ]);
    store.put(row('s', day(3, 1), 3), [
      p('s', 0, jar, -30, day(3, 1), 3, quantity: -3, sub: 'b1'),
    ]);
    expect(store.subSums(jar), {
      ('b1', twd): (amount: 70, quantity: 7), // 100 - 30, 10 - 3
      ('b2', twd): (amount: 50, quantity: 4),
    });
    expect(store.subSums(jar, until: day(1, 31)), {
      ('b1', twd): (amount: 100, quantity: 10),
    });
    store.clear();
    expect((store.intentCount, store.postingCount), (0, 0));
    expect(store.sums(), isEmpty);
    expect(store.accounts().length, 6);
  });
}
