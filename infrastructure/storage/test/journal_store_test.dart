import 'dart:io';
import 'dart:math';

import 'package:kernel/kernel.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:storage/src/journal_store.dart' show createJournalTables;
import 'package:storage/storage.dart';
import 'package:test/test.dart';

const twd = CurrencyCode('TWD');
const usd = CurrencyCode('USD');
const bank = AccountId('bank');
const food = AccountId('food');
const jar = AccountId('jar');

Posting p(
  String intent,
  int line,
  AccountId a,
  int amount,
  int ymd,
  int seq, {
  int quantity = 0,
  String sub = '',
  CurrencyCode currency = twd,
}) => Posting(
  intent: IntentId(intent),
  line: line,
  account: a,
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
  late File file;
  late StorageKey key;
  late EncryptedDatabase store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('journal-store-');
    file = File('${directory.path}/ledger.db');
    key = StorageKey.random();
    store = EncryptedDatabase.open(file, key);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  test('the journal leaves the layout version alone: a file an older '
      'version kept is given the tables, and opens in that version still', () {
    store.write((w) => w.put('entry', 'e1', '{}'));
    store.journal.keepMark((rules: 1, revision: store.revision));
    store.close();
    // As an older version keeps the file: no journal tables, layout 1,
    // and a record written by it, which moves the revision on.
    final raw = sqlite3.open(file.path)
      ..execute('PRAGMA key = "x\'${key.hex}\'"');
    expect(raw.userVersion, 1);
    raw.execute("UPDATE meta SET value = value + 1 WHERE key = 'revision'");
    for (final table in [
      'account',
      'intent_index',
      'intent_stream',
      'posting',
      'month_sum',
    ]) {
      raw.execute('DROP TABLE $table');
    }
    raw.close();
    store = EncryptedDatabase.open(file, key);
    expect(EncryptedDatabase.schema, 1);
    expect(store.rows().single.id, 'e1');
    expect(store.journal.postingCount, 0);
    // The mark is no longer the records' revision: posted afresh.
    expect(store.journal.mark, (rules: 1, revision: 1));
    expect(store.revision, 2);
    store.close();
    final again = sqlite3.open(file.path)
      ..execute('PRAGMA key = "x\'${key.hex}\'"');
    expect(again.userVersion, 1);
    again.close();
    store = EncryptedDatabase.open(file, key);
  });

  test('sums by month agree with the memory store, over any range', () {
    final r = Random(11);
    final memory = MemoryPostingStore();
    final sql = store.journal;
    sql.transaction(() {
      for (var i = 0; i < 300; i++) {
        final ymd = 20250000 + (1 + r.nextInt(12)) * 100 + 1 + r.nextInt(28);
        final amount = 1 + r.nextInt(1000);
        final id = 'i${r.nextInt(120)}';
        final ps = [
          p(id, 0, bank, -amount, ymd, i),
          p(id, 1, food, amount, ymd, i, quantity: r.nextInt(3)),
        ];
        sql.put(row(id, ymd, i), ps);
        memory.put(row(id, ymd, i), ps);
      }
      for (var k = 0; k < 15; k++) {
        final id = IntentId('i${r.nextInt(120)}');
        sql.remove(id);
        memory.remove(id);
      }
    });
    for (final (lo, hi) in [
      (0, 99991231),
      (20250301, 20250331),
      (20250215, 20250710),
      (20250115, 20250120),
      (20250101, 20250101),
      (0, 20250614),
      (20250601, 20251231),
    ]) {
      final from = lo == 0 ? null : Day.stored(lo);
      expect(
        sql.sums(from: from, until: Day.stored(hi)),
        memory.sums(from: from, until: Day.stored(hi)),
        reason: '$lo..$hi',
      );
    }
    expect(sql.postingCount, memory.postingCount);
    expect(sql.intentCount, memory.intentCount);
    // The months' sums are what their postings add up to.
    final db = store.journal;
    expect(
      db.sums(until: Day.stored(20251231)),
      memory.sums(until: Day.stored(20251231)),
    );
  });

  test('postings, streams and lots as the memory store has them', () {
    final sql = store.journal;
    sql.put(row('late', 20260103, 1, ['s']), [
      p('late', 0, jar, 3, 20260103, 1, quantity: 3, sub: 'a'),
    ]);
    sql.put(row('early', 20260101, 9, ['s']), [
      p('early', 0, jar, 1, 20260101, 9, quantity: 10, sub: 'a'),
    ]);
    sql.put(row('mid', 20260103, 0, ['s', 't']), [
      p('mid', 0, jar, 2, 20260103, 0, quantity: 5, sub: 'b'),
      p('mid', 1, bank, -2, 20260103, 0),
    ]);
    expect(
      [
        for (final r in sql.inStream(
          's',
          from: (date: Day.stored(20260102), seq: 0),
        ))
          '${r.id.value} ${r.streams.join(',')}',
      ],
      ['mid s,t', 'late s'],
    );
    expect([for (final x in sql.postingsOf(jar)) x.amount], [1, 2, 3]);
    expect(
      [
        for (final x in sql.postingsOf(
          jar,
          before: (date: Day.stored(20260103), seq: 1),
        ))
          x.amount,
      ],
      [1, 2],
    );
    expect(sql.postingsOfIntent(const IntentId('mid')), [
      p('mid', 0, jar, 2, 20260103, 0, quantity: 5, sub: 'b'),
      p('mid', 1, bank, -2, 20260103, 0),
    ]);
    expect(sql.subSums(jar), {
      ('a', twd): (amount: 4, quantity: 13), // 1 + 3, 10 + 3
      ('b', twd): (amount: 2, quantity: 5),
    });
    expect(sql.subSums(jar, until: Day.stored(20260102)), {
      ('a', twd): (amount: 1, quantity: 10),
    });
    expect(sql.intent(const IntentId('mid'))!.position, (
      date: Day.stored(20260103),
      seq: 0,
    ));
    expect(sql.intent(const IntentId('none')), isNull);
  });

  test('a transaction that throws leaves the journal as it was', () {
    final sql = store.journal;
    sql.put(row('a', 20260101, 1), [p('a', 0, bank, 5, 20260101, 1)]);
    expect(
      () => sql.transaction(() {
        sql.remove(const IntentId('a'));
        sql.keepMark((rules: 1, revision: 2));
        throw StateError('no');
      }),
      throwsStateError,
    );
    expect(sql.sums(), {(bank, twd): (amount: 5, quantity: 0)});
    expect(sql.mark, isNull);
    expect(
      () => sql.transaction(() => sql.transaction(() => 1)),
      throwsStateError,
    );
  });

  test('the tree, the mark, and clearing all but the tree', () {
    final sql = store.journal;
    const tree = [
      LedgerAccount(
        id: bank,
        cls: AccountClass.asset,
        name: '銀行',
        owner: OwnerId('accounts'),
        currency: twd,
        tag: 'bank',
      ),
      LedgerAccount(
        id: food,
        cls: AccountClass.expense,
        name: '飲食',
        owner: OwnerId('entries'),
        parent: AccountId('meals'),
        inFlowReports: false,
      ),
      LedgerAccount(
        id: jar,
        cls: AccountClass.asset,
        name: 'jar',
        owner: OwnerId('x'),
        currency: usd,
        commodity: 'beans',
        inNetWorth: false,
      ),
    ];
    sql.keepAccounts(tree);
    expect(sql.accounts(), tree);
    sql.keepMark((rules: 3, revision: 41));
    expect(sql.mark, (rules: 3, revision: 41));
    // The mark is not a change of the book.
    expect(store.revision, 0);
    sql.put(row('a', 20260101, 1, ['s']), [p('a', 0, bank, 5, 20260101, 1)]);
    sql.clear();
    expect((sql.intentCount, sql.postingCount), (0, 0));
    expect(sql.sums(), isEmpty);
    expect(sql.inStream('s', from: (date: Day.stored(0), seq: 0)), isEmpty);
    expect(sql.accounts(), tree);
  });

  group('the whole journal posted afresh apart', () {
    /// Two parts of a book: what the second has moves the first's money.
    Future<PostedApart<int>> work(
      List<KeptRow> rows,
      void Function(FreshPostingStore part) add,
    ) async {
      final one = FreshPostingStore()
        ..put(row('a', 20260101, 1, ['s']), [
          p('a', 0, bank, -5, 20260101, 1),
          p('a', 1, food, 5, 20260101, 1),
        ]);
      final two = FreshPostingStore()
        ..put(row('b', 20260215, 2), [
          p('b', 0, bank, -7, 20260215, 2),
          p('b', 1, food, 7, 20260215, 2),
        ]);
      add(one);
      add(two);
      return (
        result: rows.length,
        accounts: const [
          LedgerAccount(
            id: bank,
            cls: AccountClass.asset,
            name: 'b',
            owner: OwnerId('t'),
            currency: twd,
          ),
        ],
      );
    }

    Future<PostedApart<int>> fails(
      List<KeptRow> rows,
      void Function(FreshPostingStore part) add,
    ) async {
      add(FreshPostingStore());
      throw StateError('cut short');
    }

    test('every part written, the months summed, the mark kept last; the '
        'records and their revision untouched', () async {
      store.write(
        (w) => w
          ..put('entry', 'e1', '{}')
          ..put('trash', 't1', '{}'),
      );
      store.journal.put(row('old', 20250101, 9), [
        p('old', 0, bank, 1, 20250101, 9),
      ]);
      final revision = store.revision;
      final read = await store.postApart(
        work,
        mark: (rules: 1, revision: revision),
      );
      // The accounts, categories and entries are given: one entry here.
      expect(read, 1);
      expect(store.revision, revision);
      expect(store.journal.mark, (rules: 1, revision: revision));
      expect(store.journal.intent(const IntentId('old')), isNull);
      expect(store.journal.sums(), {
        (bank, twd): (amount: -12, quantity: 0), // -5 - 7
        (food, twd): (amount: 12, quantity: 0),
      });
      // January's sum from the months' table, February's half from the
      // postings: as the store keeps them for a single save.
      expect(store.journal.sums(until: Day.stored(20260131)), {
        (bank, twd): (amount: -5, quantity: 0),
        (food, twd): (amount: 5, quantity: 0),
      });
      expect(store.journal.postingsOfIntent(const IntentId('b')), hasLength(2));
      expect(
        store.journal.inStream('s', from: (date: Day.stored(0), seq: 0)),
        hasLength(1),
      );
      expect(store.journal.accounts().single.id, bank);
      // The indexes are there again.
      final raw = sqlite3.open(file.path)
        ..execute('PRAGMA key = "x\'${key.hex}\'"');
      store.close();
      expect(
        {
          for (final r in raw.select(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL",
          ))
            r['name'],
        },
        containsAll([
          'intent_id',
          'intent_stream_intent',
          'month_sum_month',
          'posting_date',
          'posting_account',
        ]),
      );
      raw.close();
      store = EncryptedDatabase.open(file, key);
    });

    test('one worker at a time: a posting afresh is refused while a read '
        'or a write runs apart, and the others while it runs', () async {
      store.write((w) => w.put('entry', 'e1', '{}'));
      final reading = store.readApart((snapshot) async => snapshot.rows.length);
      expect(
        () => store.postApart(work, mark: (rules: 1, revision: 1)),
        throwsStateError,
      );
      expect(await reading, 1);
      await store.idle;
      final posting = store.postApart(work, mark: (rules: 1, revision: 1));
      expect(store.busyApart, isTrue);
      expect(() => store.readApart((snapshot) async => 0), throwsStateError);
      expect(
        () => store.writeApart(const [RowChange.drop('entry', 'e1')]),
        throwsStateError,
      );
      expect(() => store.journal.postingCount, throwsStateError);
      await posting;
      expect(store.busyApart, isFalse);
      expect(store.journal.mark, (rules: 1, revision: 1));
    });

    test(
      'cut short, it leaves the journal and its mark as they were',
      () async {
        store.journal.put(row('old', 20250101, 9), [
          p('old', 0, bank, 1, 20250101, 9),
        ]);
        store.journal.keepMark((rules: 1, revision: 0));
        await expectLater(
          store.postApart(fails, mark: (rules: 1, revision: 5)),
          throwsStateError,
        );
        expect(store.journal.mark, (rules: 1, revision: 0));
        expect(store.journal.intent(const IntentId('old')), isNotNull);
        expect(store.busyApart, isFalse);
      },
    );
  });

  test('a fill puts the connection back as it was, finished or abandoned: '
      'the records keep their durability', () {
    final db = sqlite3.openInMemory()
      ..execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value INTEGER)')
      ..execute('PRAGMA synchronous = FULL')
      ..execute('PRAGMA cache_size = -1234');
    addTearDown(db.close);
    createJournalTables(db);
    final sql = SqlPostingStore(db);
    Object? pragma(String name) =>
        db.select('PRAGMA $name').single.values.single;
    final was = (pragma('synchronous'), pragma('cache_size'));

    final fill = sql.begin();
    expect(pragma('synchronous'), isNot(was.$1), reason: 'eased inside');
    fill
      ..add(
        FreshPostingStore()..put(row('a', 20260101, 1), [
          p('a', 0, bank, -5, 20260101, 1),
          p('a', 1, food, 5, 20260101, 1),
        ]),
      )
      ..finish(accounts: const [], mark: (rules: 1, revision: 3));
    expect((pragma('synchronous'), pragma('cache_size')), was);
    expect(sql.mark, (rules: 1, revision: 3));

    sql.begin().abandon();
    expect((pragma('synchronous'), pragma('cache_size')), was);
    expect(sql.intentCount, 1, reason: 'abandoned: as it was');
  });

  test('a journal writes through it: put, refuse, take away', () {
    final journal = Journal(
      registry: IntentRegistry()
        ..register<_Move>(
          const IntentSpec(
            type: _Move.kind,
            owner: OwnerId('t'),
            rule: _MoveRule(),
          ),
        ),
      accounts: AccountTree([
        const LedgerAccount(
          id: bank,
          cls: AccountClass.asset,
          name: 'b',
          owner: OwnerId('t'),
          currency: twd,
        ),
        const LedgerAccount(
          id: food,
          cls: AccountClass.expense,
          name: 'f',
          owner: OwnerId('t'),
        ),
      ]),
      store: store.journal,
      source: (_) => null,
    );
    expect(journal.put(_Move('m', 20260105, 120)), isA<Written>());
    expect(journal.put(_Move('n', 20260106, -1)), isA<RuleRejected>());
    expect(store.journal.sums(), {
      (bank, twd): (amount: -120, quantity: 0),
      (food, twd): (amount: 120, quantity: 0),
    });
    expect(journal.delete(const IntentId('m')), isA<Written>());
    expect(store.journal.sums(), isEmpty);
    // The journal's writes are not changes of the records.
    expect(store.revision, 0);
  });
}

final class _Move extends LedgerIntent {
  _Move(String id, int ymd, this.amount)
    : super(id: IntentId(id), date: Day.stored(ymd), seq: 1);
  static const kind = IntentType('move');
  final int amount;
  @override
  IntentType get type => kind;
}

final class _MoveRule implements PostingRule<_Move> {
  const _MoveRule();
  @override
  Iterable<String> streams(_Move intent) => const [];
  @override
  Posted post(_Move i, RuleContext context) => i.amount <= 0
      ? const Refused('badAmount')
      : Lines([Line(bank, -i.amount, twd), Line(food, i.amount, twd)]);
}
