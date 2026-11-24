// The whole/part quantity columns against the memory store.
import 'dart:io';
import 'dart:math';

import 'package:kernel/kernel.dart';
import 'package:storage/storage.dart';
import 'package:test/test.dart';

const twd = CurrencyCode('TWD');

Posting p(
  String intent,
  int line,
  String a,
  int amount,
  int ymd,
  int seq, {
  BigInt? quantity,
  String sub = '',
}) => Posting(
  intent: IntentId(intent),
  line: line,
  account: AccountId(a),
  amount: amount,
  currency: twd,
  date: Day.stored(ymd),
  seq: seq,
  quantity: quantity,
  sub: sub,
);

IntentRow row(String id, int ymd, int seq, [List<String> streams = const []]) =>
    IntentRow(
      id: IntentId(id),
      type: const IntentType('t'),
      date: Day.stored(ymd),
      seq: seq,
      streams: streams,
    );

final unit = quantityScale;
BigInt q(int whole, int parts) =>
    BigInt.from(whole) * unit + BigInt.from(parts);

void main() {
  late Directory directory;
  late EncryptedDatabase store;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('r14q-');
    store = EncryptedDatabase.open(
      File('${directory.path}/l.db'),
      StorageKey.random(),
    );
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  // Two quantities each under maxQuantity (kept per posting) whose total is
  // over what the `units` column's SUM can hold: the store must answer the
  // exact sum, as the memory store does, or refuse the posting that makes it.
  test(
    'sums of quantities that are each keepable but together pass 2^63 units',
    () {
      final big = maxQuantity; // each keepable
      final mem = MemoryPostingStore();
      final sql = store.journal;
      for (final s in [mem, sql]) {
        s.transaction(() {
          s.put(row('a', 20260110, 1), [
            p('a', 0, 'h', 0, 20260110, 1, quantity: big, sub: 'x'),
          ]);
          s.put(row('b', 20260210, 2), [
            p('b', 0, 'h', 0, 20260210, 2, quantity: big, sub: 'x'),
          ]);
        });
      }
      expect(
        sql.sums()[(const AccountId('h'), twd)]?.quantity,
        mem.sums()[(const AccountId('h'), twd)]?.quantity,
        reason: 'sums() over both months',
      );
      expect(
        sql.subSums(const AccountId('h'))[('x', twd)]?.quantity,
        mem.subSums(const AccountId('h'))[('x', twd)]?.quantity,
        reason: 'subSums()',
      );
    },
  );

  test('one intent with two keepable lines in one month that pass 2^63 units '
      'is refused or kept, never thrown out of put as ArgumentError', () {
    final big = maxQuantity;
    final sql = store.journal;
    Object? thrown;
    try {
      sql.transaction(() {
        sql.put(row('a', 20260110, 1), [
          p('a', 0, 'h', 0, 20260110, 1, quantity: big, sub: 'x'),
          p('a', 1, 'h', 0, 20260110, 1, quantity: big, sub: 'y'),
        ]);
      });
    } catch (e) {
      thrown = e;
    }
    // The memory store keeps it; the file's store must too.
    expect(thrown, isNull, reason: 'put threw ${thrown.runtimeType}: $thrown');
  });

  test('random fractional, negative and borrowing quantities: file == memory '
      'over every range, after removals', () {
    final r = Random(14);
    final mem = MemoryPostingStore();
    final sql = store.journal;
    for (final s in [mem, sql]) {
      final rr = Random(14);
      s.transaction(() {
        for (var i = 0; i < 600; i++) {
          final ymd = 20260000 + (1 + rr.nextInt(6)) * 100 + 1 + rr.nextInt(28);
          final id = 'i${rr.nextInt(120)}';
          final whole = rr.nextInt(5) - 2;
          final parts =
              (rr.nextInt(1000000) * 1000000 + rr.nextInt(1000000)) *
              (rr.nextBool() ? 1 : -1);
          final qty = q(whole, parts);
          s.put(row(id, ymd, i, ['s']), [
            p(id, 0, 'h', 0, ymd, i, quantity: qty, sub: 's${rr.nextInt(3)}'),
            p(id, 1, 'h2', 0, ymd, i, quantity: -qty, sub: 's0'),
          ]);
          if (rr.nextInt(6) == 0) s.remove(IntentId('i${rr.nextInt(120)}'));
        }
      });
    }
    String show(AccountSums m) =>
        '${m.entries.map((e) => '${e.key.$1.value}=${e.value.amount}/${e.value.quantity}').toList()..sort()}';
    for (var k = 0; k < 300; k++) {
      final a = 20260000 + (1 + r.nextInt(6)) * 100 + 1 + r.nextInt(30);
      final b = 20260000 + (1 + r.nextInt(6)) * 100 + 1 + r.nextInt(30);
      final from = r.nextInt(4) == 0 ? null : Day.stored(a);
      final until = r.nextInt(4) == 0 ? null : Day.stored(b);
      expect(
        show(sql.sums(from: from, until: until)),
        show(mem.sums(from: from, until: until)),
        reason: '${from?.ymd}..${until?.ymd}',
      );
    }
    // After a whole refill (fill's months built at the end) the same sums.
    final part = FreshPostingStore();
    for (final id in [for (var i = 0; i < 120; i++) 'i$i']) {
      final it = mem.intent(IntentId(id));
      if (it == null) continue;
      part.put(it, mem.postingsOfIntent(IntentId(id)));
    }
    final fill = sql.begin();
    fill.add(part);
    fill.finish(accounts: const [], mark: (rules: 1, revision: 1));
    expect(show(sql.sums()), show(mem.sums()));
    for (final m in [1, 2, 3, 4, 5, 6]) {
      final from = Day.stored(20260000 + m * 100 + 1),
          until = Day.stored(20260000 + m * 100 + 31);
      expect(
        show(sql.sums(from: from, until: until)),
        show(mem.sums(from: from, until: until)),
        reason: 'month $m after fill',
      );
    }
  });
}
