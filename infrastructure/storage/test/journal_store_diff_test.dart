// The file's journal store against the memory store, the kernel's own:
// the same postings, the same sums over any range (an inverted one
// included), the same history before any place, lots and streams
// (review 9's differential, kept).
import 'dart:io';
import 'dart:math';

import 'package:kernel/kernel.dart';
import 'package:storage/storage.dart';
import 'package:test/test.dart';

const twd = CurrencyCode('TWD');
const usd = CurrencyCode('USD');

Posting p(
  String intent,
  int line,
  String a,
  int amount,
  int ymd,
  int seq, {
  BigInt? quantity,
  String sub = '',
  CurrencyCode currency = twd,
}) => Posting(
  intent: IntentId(intent),
  line: line,
  account: AccountId(a),
  amount: amount,
  currency: currency,
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

void main() {
  late Directory directory;
  late EncryptedDatabase store;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('jd-');
    store = EncryptedDatabase.open(
      File('${directory.path}/l.db'),
      StorageKey.random(),
    );
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  test('inverted range: from after until', () {
    final mem = MemoryPostingStore();
    final sql = store.journal;
    for (final s in [mem, sql]) {
      s.transaction(() {
        s.put(row('a', 20261002, 1), [
          p('a', 0, 'bank', -5, 20261002, 1),
          p('a', 1, 'food', 5, 20261002, 1),
        ]);
        s.put(row('b', 20261120, 2), [
          p('b', 0, 'bank', -7, 20261120, 2),
          p('b', 1, 'food', 7, 20261120, 2),
        ]);
      });
    }
    final from = Day.stored(20261101), until = Day.stored(20261004);
    expect(sql.sums(from: from, until: until), isEmpty);
    expect(
      sql.sums(from: from, until: until),
      mem.sums(from: from, until: until),
    );
  });

  test('random differential: sums over any range incl. across years, '
      'postingsOf before, subSums, inStream', () {
    final r = Random(5);
    final mem = MemoryPostingStore();
    final sql = store.journal;
    final bad = <String>[];
    for (final s in [mem, sql]) {
      final rr = Random(5);
      s.transaction(() {
        for (var i = 0; i < 400; i++) {
          final y = 2024 + rr.nextInt(3);
          final m = 1 + rr.nextInt(12);
          final d = 1 + rr.nextInt(28);
          final ymd = y * 10000 + m * 100 + d;
          final amount = 1 + rr.nextInt(1000);
          final id = 'i${rr.nextInt(150)}';
          final seq = rr.nextInt(300);
          final pd = rr.nextInt(4) == 0 ? ymd + 100 * (rr.nextInt(2) + 1) : ymd;
          final ps = [
            p(
              id,
              0,
              'bank',
              -amount,
              pd > 20261231 ? ymd : pd,
              seq,
              currency: rr.nextBool() ? twd : usd,
            ),
            p(
              id,
              1,
              'food',
              amount,
              ymd,
              seq,
              // Whole shares and parts of one, either sign (D87).
              quantity:
                  quantityOfUnits(rr.nextInt(3) - 1) +
                  BigInt.from(rr.nextInt(1000000)) * BigInt.from(997),
              sub: 's${rr.nextInt(3)}',
            ),
          ];
          // keep the two lines in one currency for simplicity
          final cur = ps[0].currency;
          s.put(row(id, ymd, seq, ['st${rr.nextInt(3)}']), [
            ps[0],
            Posting(
              intent: ps[1].intent,
              line: 1,
              account: ps[1].account,
              amount: ps[1].amount,
              currency: cur,
              date: ps[1].date,
              seq: seq,
              quantity: ps[1].quantity,
              sub: ps[1].sub,
            ),
          ]);
          if (rr.nextInt(10) == 0) s.remove(IntentId('i${rr.nextInt(150)}'));
        }
      });
    }
    for (var k = 0; k < 400; k++) {
      final a =
          (2023 + r.nextInt(5)) * 10000 +
          (1 + r.nextInt(12)) * 100 +
          1 +
          r.nextInt(30);
      final b =
          (2023 + r.nextInt(5)) * 10000 +
          (1 + r.nextInt(12)) * 100 +
          1 +
          r.nextInt(30);
      final from = r.nextInt(5) == 0 ? null : Day.stored(a);
      final until = r.nextInt(5) == 0 ? null : Day.stored(b);
      final x = mem.sums(from: from, until: until),
          y = sql.sums(from: from, until: until);
      if ('${x.entries.map((e) => '${e.key}${e.value}').toList()..sort()}' !=
          '${y.entries.map((e) => '${e.key}${e.value}').toList()..sort()}') {
        bad.add(
          'sums ${from?.ymd}..${until?.ymd} inverted=${from != null && until != null && from > until}',
        );
      }
    }
    for (var k = 0; k < 100; k++) {
      final pos = (
        date: Day.stored(
          2024 * 10000 +
              (1 + r.nextInt(36)) ~/ 3 * 100 +
              1 +
              r.nextInt(28) +
              (r.nextInt(3)) * 10000,
        ),
        seq: r.nextInt(300),
      );
      final x = mem
          .postingsOf(const AccountId('bank'), before: pos)
          .map((e) => e.toString())
          .toList();
      final y = sql
          .postingsOf(const AccountId('bank'), before: pos)
          .map((e) => e.toString())
          .toList();
      if (x.join() != y.join()) {
        bad.add('postingsOf before $pos: ${x.length} vs ${y.length}');
      }
      final xs = mem.inStream('st1', from: pos).map((e) => e.id.value).toList();
      final ys = sql.inStream('st1', from: pos).map((e) => e.id.value).toList();
      if (xs.join(',') != ys.join(',')) bad.add('inStream $pos');
    }
    for (final u in [null, Day.stored(20250615), Day.stored(20240101)]) {
      final x = mem.subSums(const AccountId('food'), until: u);
      final y = sql.subSums(const AccountId('food'), until: u);
      if ('${x.entries.map((e) => '${e.key}${e.value}').toList()..sort()}' !=
          '${y.entries.map((e) => '${e.key}${e.value}').toList()..sort()}') {
        bad.add('subSums until ${u?.ymd}');
      }
    }
    expect(bad, isEmpty);
  });

  test('an abandoned or failed fill leaves the old journal and mark intact', () {
    final sql = store.journal;
    sql.transaction(() {
      sql.put(row('a', 20261002, 1, ['s']), [
        p('a', 0, 'bank', -5, 20261002, 1),
        p('a', 1, 'food', 5, 20261002, 1),
      ]);
      sql.keepMark((rules: 1, revision: 7));
      sql.keepAccounts([
        const LedgerAccount(
          id: AccountId('bank'),
          cls: AccountClass.asset,
          name: 'b',
          owner: OwnerId('o'),
          currency: twd,
        ),
      ]);
    });
    String state() =>
        '${sql.mark} ${sql.intentCount} ${sql.postingCount} ${sql.sums()} ${sql.accounts().length} ${sql.inStream('s', from: (date: Day.stored(0), seq: 0)).length}';
    final before = state();
    final part = FreshPostingStore()
      ..put(row('z', 20261003, 2), [
        p('z', 0, 'bank', -9, 20261003, 2),
        p('z', 1, 'food', 9, 20261003, 2),
      ]);
    final fill = sql.begin();
    fill.add(part);
    fill.abandon();
    expect(state(), before);
    // finish failing: duplicate intent id across parts violates the key
    final fill2 = sql.begin();
    fill2.add(part);
    Object? err;
    try {
      fill2.add(part);
      fill2.finish(accounts: const [], mark: (rules: 1, revision: 8));
    } catch (e) {
      err = e;
    } finally {
      fill2.abandon();
    }
    // ignore: avoid_print
    print(
      'finish with a duplicate part threw: ${err.runtimeType}; state intact: ${state() == before}',
    );
    expect(state(), before);
    // the connection is usable and in autocommit after
    sql.transaction(() => sql.remove(const IntentId('a')));
  });
}
