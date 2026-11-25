// A bulk fill cut short (killed between its steps, or failing
// part-way) leaves the journal and its mark as they were, and the integer
// keys of accounts stable.
import 'dart:io';

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

String state(SqlPostingStore s) =>
    '${s.mark} ${s.intentCount} ${s.postingCount} '
    '${(s.sums().entries.map((e) => '${e.key.$1.value}=${e.value.amount}').toList()..sort())} '
    '${s.inStream('s', from: startOfBook).map((r) => r.id.value).toList()} '
    '${s.postingsOf(const AccountId('bank')).map((x) => x.amount).toList()}';

void main() {
  late Directory directory;
  late StorageKey key;
  late EncryptedDatabase store;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('r14f-');
    key = StorageKey.random();
    store = EncryptedDatabase.open(File('${directory.path}/l.db'), key);
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  void seed(SqlPostingStore sql) => sql.transaction(() {
    sql.put(row('a', 20261002, 1, ['s']), [
      p('a', 0, 'bank', -5, 20261002, 1),
      p('a', 1, 'food', 5, 20261002, 1),
    ]);
    sql.put(row('b', 20261102, 2, ['s']), [
      p('b', 0, 'bank', -7, 20261102, 2),
      p('b', 1, 'food', 7, 20261102, 2),
    ]);
    sql.keepMark((rules: 3, revision: 9));
  });

  FreshPostingStore part() => FreshPostingStore()
    ..put(row('z', 20261003, 3, ['s']), [
      p('z', 0, 'bank', -9, 20261003, 3),
      p('z', 1, 'new', 9, 20261003, 3),
    ]);

  test('the file as it stands in the middle of a fill (a kill there) opens as '
      'the journal before the fill, mark and all', () {
    final sql = store.journal;
    seed(sql);
    final before = state(sql);
    final fill = sql.begin();
    fill.add(part());
    // What a process killed here leaves on disk: the file and its WAL as
    // they are, copied while the fill's transaction is open.
    final copy = Directory('${directory.path}/crash')..createSync();
    for (final f in directory.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.startsWith('l.db')) f.copySync('${copy.path}/$name');
    }
    fill.abandon();
    final crashed = EncryptedDatabase.open(File('${copy.path}/l.db'), key);
    addTearDown(crashed.close);
    expect(state(crashed.journal), before);
    // And it still posts and reads (the indexes are there).
    crashed.journal.transaction(
      () => crashed.journal.put(row('c', 20261201, 4, ['s']), [
        p('c', 0, 'bank', -1, 20261201, 4),
        p('c', 1, 'food', 1, 20261201, 4),
      ]),
    );
    expect(crashed.journal.postingsOf(const AccountId('bank')).length, 3);
  });

  test(
    'a part that cannot be written (a quantity past what is kept) leaves the '
    'journal as it was and gives no account a key it keeps',
    () {
      final sql = store.journal;
      seed(sql);
      final before = state(sql);
      final bad = FreshPostingStore()
        ..put(row('y', 20261003, 3), [
          p('y', 0, 'bank', 0, 20261003, 3),
          p(
            'y',
            1,
            'brand-new',
            0,
            20261003,
            3,
            quantity: maxQuantity + BigInt.one,
          ),
        ]);
      final fill = sql.begin();
      Object? thrown;
      try {
        fill.add(bad);
      } catch (e) {
        thrown = e;
      } finally {
        fill.abandon();
      }
      expect(thrown, isNotNull);
      expect(state(sql), before);
      // The next fill and a put on the same account read back as posted.
      final ok = sql.begin();
      ok.add(part());
      ok.finish(accounts: const [], mark: (rules: 3, revision: 10));
      expect(sql.postingsOf(const AccountId('new')).single.amount, 9);
      expect(sql.postingsOf(const AccountId('bank')).single.amount, -9);
      expect(sql.mark, (rules: 3, revision: 10));
    },
  );

  test('integer keys of accounts and intents outlive a refill: the same '
      'account has the same key before and after, and a rebuild in another '
      'order reads back the same book', () {
    final sql = store.journal;
    seed(sql);
    final first = sql
        .postingsOf(const AccountId('food'))
        .map((x) => x.toString())
        .toList();
    // Refill with the parts in another order of accounts and intents.
    final reverse = FreshPostingStore()
      ..put(row('b', 20261102, 2, ['s']), [
        p('b', 0, 'food', 7, 20261102, 2),
        p('b', 1, 'bank', -7, 20261102, 2),
      ])
      ..put(row('a', 20261002, 1, ['s']), [
        p('a', 0, 'food', 5, 20261002, 1),
        p('a', 1, 'bank', -5, 20261002, 1),
      ]);
    final fill = sql.begin();
    fill.add(reverse);
    fill.finish(accounts: const [], mark: (rules: 3, revision: 9));
    expect(
      sql.postingsOf(const AccountId('food')).map((x) => x.toString()).toList(),
      first.map((s) => s.replaceFirst('#1', '#0')).toList(),
    );
    // Then a put of an old intent's id replaces it, never duplicates it.
    sql.transaction(
      () => sql.put(row('a', 20261002, 1, ['s']), [
        p('a', 0, 'bank', -6, 20261002, 1),
        p('a', 1, 'food', 6, 20261002, 1),
      ]),
    );
    expect(sql.intentCount, 2);
    expect(sql.postingCount, 4);
    expect(sql.sums()[(const AccountId('food'), twd)]!.amount, 13);
  });
}
