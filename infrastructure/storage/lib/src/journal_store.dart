import 'package:kernel/kernel.dart';
import 'package:sqlite3/sqlite3.dart';

/// The journal's tables beside the records, made when missing as the file
/// opens. Outside the layout's version ladder on purpose (decision D49):
/// an older version, which checks that version, opens the file and leaves
/// these tables alone; the records it writes then move the revision past
/// the journal's mark, and the journal is posted afresh. All of them are
/// derived from the records (`rows`): they can be dropped and posted
/// again, a backup does not carry them, and a record set aside has no
/// postings. The body of an intent stays in its row.
///
/// Intents and accounts are named in the postings, the months' sums and
/// the streams by a number of their own ([SqlPostingStore] keeps which
/// stands for which): a posting row a third of the size, written and
/// sorted in half the time (D51). A quantity is kept exactly (D87) as
/// its whole units and its parts ([quantityScale] to a unit, the same
/// sign), each summed by SQL in two halves (its high bits and its low 32)
/// and put together after: a sum of many rows never passes what SQL's
/// integers hold (r14 F6). A month's sum keeps those halves. Tables of an
/// earlier shape are dropped and made again, the journal then posted
/// afresh.
void createJournalTables(Database db) {
  final posting = _columns(db, 'posting');
  final months = _columns(db, 'month_sum');
  if ((posting.isNotEmpty && !posting.contains('parts')) ||
      (months.isNotEmpty && !months.contains('units_lo'))) {
    for (final table in _journalTables) {
      db.execute('DROP TABLE IF EXISTS $table');
    }
    db.execute(
      "DELETE FROM meta WHERE key IN ('${SqlPostingStore._rulesKey}', "
      "'${SqlPostingStore._revisionKey}')",
    );
  }
  db.execute('''
    CREATE TABLE IF NOT EXISTS account (
      id TEXT PRIMARY KEY,
      class TEXT NOT NULL,
      name TEXT NOT NULL,
      owner TEXT NOT NULL,
      parent TEXT,
      currency TEXT,
      commodity TEXT,
      tag TEXT NOT NULL,
      in_net_worth INTEGER NOT NULL,
      in_flow_reports INTEGER NOT NULL
    ) STRICT, WITHOUT ROWID
  ''');
  // The number each account is named by, once given never taken back.
  db.execute('''
    CREATE TABLE IF NOT EXISTS account_key (
      key INTEGER PRIMARY KEY,
      id TEXT NOT NULL UNIQUE
    ) STRICT
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS intent_index (
      key INTEGER PRIMARY KEY,
      id TEXT NOT NULL,
      type TEXT NOT NULL,
      date INTEGER NOT NULL,
      seq INTEGER NOT NULL
    ) STRICT
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS intent_stream (
      stream TEXT NOT NULL,
      date INTEGER NOT NULL,
      seq INTEGER NOT NULL,
      intent INTEGER NOT NULL,
      PRIMARY KEY (stream, date, seq, intent)
    ) STRICT, WITHOUT ROWID
  ''');
  // In the order of its key, as a whole book is written: each row lands
  // at the end of the tree.
  db.execute('''
    CREATE TABLE IF NOT EXISTS posting (
      intent INTEGER NOT NULL,
      line INTEGER NOT NULL,
      account INTEGER NOT NULL,
      currency TEXT NOT NULL,
      amount INTEGER NOT NULL,
      units INTEGER NOT NULL,
      parts INTEGER NOT NULL,
      sub TEXT NOT NULL,
      date INTEGER NOT NULL,
      seq INTEGER NOT NULL,
      PRIMARY KEY (intent, line)
    ) STRICT, WITHOUT ROWID
  ''');
  // Each month's sum by account, kept in the same transaction as the
  // postings: every balance is the months before plus this month's.
  db.execute('''
    CREATE TABLE IF NOT EXISTS month_sum (
      account INTEGER NOT NULL,
      currency TEXT NOT NULL,
      month INTEGER NOT NULL,
      amount INTEGER NOT NULL,
      units_hi INTEGER NOT NULL,
      units_lo INTEGER NOT NULL,
      parts_hi INTEGER NOT NULL,
      parts_lo INTEGER NOT NULL,
      PRIMARY KEY (account, currency, month)
    ) STRICT, WITHOUT ROWID
  ''');
  _journalIndexes.values.forEach(db.execute);
}

/// The journal's tables, the account tree's and the accounts' numbers
/// last.
const _journalTables = [
  'posting',
  'intent_stream',
  'intent_index',
  'month_sum',
  'account',
  'account_key',
];

Set<String> _columns(Database db, String table) => {
  for (final r in db.select('PRAGMA table_info($table)')) r['name'] as String,
};

/// The journal's indexes, by name, each one a query reads through (see
/// the query beside each). Posting a whole book afresh drops them and
/// makes them again once every row is in ([SqlPostingStore.begin]): one
/// sort each, in place of one insertion per row.
const _journalIndexes = {
  // An intent by its id: intent, put, remove, postingsOfIntent.
  'intent_id':
      'CREATE UNIQUE INDEX IF NOT EXISTS intent_id ON intent_index (id)',
  // An intent's streams: intent, inStream.
  'intent_stream_intent':
      'CREATE INDEX IF NOT EXISTS intent_stream_intent '
      'ON intent_stream (intent)',
  // A period's whole months by month: sums from a day after the start.
  'month_sum_month':
      'CREATE INDEX IF NOT EXISTS month_sum_month '
      'ON month_sum (month, account, currency, amount, units_hi, units_lo, '
      'parts_hi, parts_lo)',
  // The days of a month cut by a period's end: sums.
  'posting_date': 'CREATE INDEX IF NOT EXISTS posting_date ON posting (date)',
  // One account's history in book order: postingsOf, daySums, subSums.
  'posting_account':
      'CREATE INDEX IF NOT EXISTS posting_account '
      'ON posting (account, date, seq)',
};

/// The connection's settings a fill changes for its own transaction.
typedef _Pragmas = ({Object? cache, Object? synchronous});

/// A record as kept: its shelf, its id there, its place, its body.
typedef KeptRow = ({String shelf, String id, int seq, String body});

/// A month's sums being added up: by account number, currency and month.
typedef _MonthKey = (int, String, int);

/// Posting a whole book afresh, under way in one transaction
/// ([SqlPostingStore.begin]): parts added as they are posted, then
/// finished, or abandoned with nothing changed.
final class JournalFill {
  JournalFill._(this._store, this._was);

  final SqlPostingStore _store;
  final _Pragmas _was;
  final _months = <_MonthKey, (int, BigInt)>{};
  var _next = 1;
  var _done = false;

  /// Writes the intents and postings of [part].
  void add(FreshPostingStore part) {
    if (_done) throw StateError('fill done');
    _next = _store._add(part, _months, _next);
  }

  /// Makes the indexes and the months' sums, keeps [accounts] as the tree
  /// and [mark] last, and commits.
  void finish({
    required List<LedgerAccount> accounts,
    required JournalMark mark,
  }) {
    if (_done) throw StateError('fill done');
    _done = true;
    try {
      _store._finish(_months, accounts, mark);
    } catch (_) {
      _store._rollBack();
      rethrow;
    } finally {
      _store._restore(_was);
    }
  }

  /// Lets go of everything added: the journal as it was.
  void abandon() {
    if (_done) return;
    _done = true;
    _store._rollBack();
    _store._restore(_was);
  }
}

/// What posting a whole book afresh answers: its own [result], and the
/// account tree its postings name.
typedef PostedApart<T> = ({T result, List<LedgerAccount> accounts});

/// The journal's [PostingStore] on the ledger's own file.
final class SqlPostingStore implements PostingStore {
  SqlPostingStore(this._db, [this._check = _always]);

  final Database _db;
  var _inTransaction = false;
  final _statements = <String, PreparedStatement>{};

  /// Each account's number, and back ([_accountKey]); read from the file
  /// as they are asked for, forgotten when a transaction is let go.
  final _keyOf = <AccountId, int>{};
  final _accountOf = <int, AccountId>{};

  /// The meta keys the mark is kept under.
  static const _rulesKey = 'journal.rules';
  static const _revisionKey = 'journal.revision';

  /// Past the last day any book holds.
  static final _end = Day.afterAll.ymd;

  /// Throws when the file may not be used now: closed, or written on
  /// another isolate (the store's own check).
  final void Function() _check;

  static void _always() {}

  PreparedStatement _sql(String sql) {
    _check();
    return _statements[sql] ??= _db.prepare(sql, persistent: true);
  }

  void _rollBack() {
    if (!_db.autocommit) _db.execute('ROLLBACK');
    // Account numbers given in a transaction let go are not in the file.
    _keyOf.clear();
    _accountOf.clear();
  }

  /// Lets the prepared statements go, before the file is closed.
  void close() {
    for (final s in _statements.values) {
      s.close();
    }
    _statements.clear();
  }

  /// The number [account] is named by in the tables; one is given the
  /// first time it is asked for.
  int _accountKey(AccountId account) =>
      _keyIfAny(account) ??
      _known(account, () {
        _sql('INSERT INTO account_key (id) VALUES (?)')
            .execute([account.value]);
        return _db.lastInsertRowId;
      });

  /// The number [account] is named by, or null when nothing has named it
  /// (so nothing is posted on it); none is given.
  int? _keyIfAny(AccountId account) {
    final known = _keyOf[account];
    if (known != null) return known;
    final found = _sql('SELECT key FROM account_key WHERE id = ?')
        .select([account.value]);
    if (found.isEmpty) return null;
    return _known(account, () => found.single['key'] as int);
  }

  int _known(AccountId account, int Function() key) {
    final k = key();
    _keyOf[account] = k;
    _accountOf[k] = account;
    return k;
  }

  /// The account named by [key] in the tables.
  AccountId _account(int key) {
    final known = _accountOf[key];
    if (known != null) return known;
    final account = AccountId(
      _sql('SELECT id FROM account_key WHERE key = ?')
              .select([key])
              .single['id']
          as String,
    );
    _known(account, () => key);
    return account;
  }

  @override
  JournalMark? get mark {
    int? read(String key) =>
        switch (_sql('SELECT value FROM meta WHERE key = ?').select([key])) {
          final rows when rows.isNotEmpty => rows.single['value'] as int,
          _ => null,
        };
    final rules = read(_rulesKey);
    final revision = read(_revisionKey);
    return rules == null || revision == null
        ? null
        : (rules: rules, revision: revision);
  }

  @override
  void keepMark(JournalMark mark) {
    final put = _sql(
      'INSERT INTO meta (key, value) VALUES (?, ?) '
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
    );
    put.execute([_rulesKey, mark.rules]);
    put.execute([_revisionKey, mark.revision]);
  }

  @override
  T transaction<T>(T Function() body) {
    if (_inTransaction) throw StateError('nested transaction');
    _check();
    _inTransaction = true;
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _rollBack();
      rethrow;
    } finally {
      _inTransaction = false;
    }
  }

  IntentRow _row(Row r) => IntentRow(
    id: IntentId(r['id'] as String),
    type: IntentType(r['type'] as String),
    date: Day.stored(r['date'] as int),
    seq: r['seq'] as int,
    streams: [
      for (final s in _sql(
        'SELECT stream FROM intent_stream WHERE intent = ? ORDER BY stream',
      ).select([r['key']]))
        s['stream'] as String,
    ],
  );

  /// A posting row, its intent's id read beside it (`intent_id`).
  Posting _posting(Row r) => Posting(
    intent: IntentId(r['intent_id'] as String),
    line: r['line'] as int,
    account: _account(r['account'] as int),
    amount: r['amount'] as int,
    currency: CurrencyCode(r['currency'] as String),
    date: Day.stored(r['date'] as int),
    seq: r['seq'] as int,
    quantity:
        BigInt.from(r['units'] as int) * quantityScale +
        BigInt.from(r['parts'] as int),
    sub: r['sub'] as String,
  );

  @override
  IntentRow? intent(IntentId id) {
    final rows = _sql('SELECT * FROM intent_index WHERE id = ?')
        .select([id.value]);
    return rows.isEmpty ? null : _row(rows.single);
  }

  @override
  void put(IntentRow row, List<Posting> postings) {
    // Kept before: what it had goes first.
    remove(row.id);
    _sql('INSERT INTO intent_index (id, type, date, seq) VALUES (?, ?, ?, ?)')
        .execute([row.id.value, row.type.value, row.date.ymd, row.seq]);
    final key = _db.lastInsertRowId;
    final stream = _sql(
      'INSERT OR IGNORE INTO intent_stream (stream, date, seq, intent) '
      'VALUES (?, ?, ?, ?)',
    );
    for (final s in row.streams) {
      stream.execute([s, row.date.ymd, row.seq, key]);
    }
    final insert = _sql(
      'INSERT INTO posting (intent, line, account, currency, amount, '
      'units, parts, sub, date, seq) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    );
    final months = <_MonthKey, (int, BigInt)>{};
    for (final p in postings) {
      final account = _accountKey(p.account);
      final (units, parts) = _split(p.quantity);
      insert.execute([
        key,
        p.line,
        account,
        p.currency.value,
        p.amount,
        units,
        parts,
        p.sub,
        p.date.ymd,
        row.seq,
      ]);
      final month = (account, p.currency.value, p.date.monthKey);
      final (amount, quantity) = months[month] ?? (0, BigInt.zero);
      months[month] = (amount + p.amount, quantity + p.quantity);
    }
    for (final MapEntry(key: (account, currency, month), value: (a, q))
        in months.entries) {
      _addToMonth(account, currency, month, a, q);
    }
  }

  @override
  void remove(IntentId id) {
    final found = _sql('SELECT key FROM intent_index WHERE id = ?')
        .select([id.value]);
    if (found.isEmpty) return;
    final key = found.single['key'] as int;
    for (final r in _sql(
      'SELECT account, currency, date / 100 AS month, SUM(amount) AS amount, '
      '$_postingQuantitySums FROM posting '
      'WHERE intent = ? GROUP BY account, currency, month',
    ).select([key])) {
      _addToMonth(
        r['account'] as int,
        r['currency'] as String,
        r['month'] as int,
        -(r['amount'] as int),
        -_quantity(r),
      );
    }
    _sql('DELETE FROM posting WHERE intent = ?').execute([key]);
    _sql('DELETE FROM intent_stream WHERE intent = ?').execute([key]);
    _sql('DELETE FROM intent_index WHERE key = ?').execute([key]);
  }

  void _addToMonth(
    int account,
    String currency,
    int month,
    int amount,
    BigInt quantity,
  ) {
    _sql(
      'INSERT INTO month_sum (account, currency, month, amount, units_hi, '
      'units_lo, parts_hi, parts_lo) VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (account, currency, month) '
      'DO UPDATE SET amount = amount + excluded.amount, '
      'units_hi = units_hi + excluded.units_hi, '
      'units_lo = units_lo + excluded.units_lo, '
      'parts_hi = parts_hi + excluded.parts_hi, '
      'parts_lo = parts_lo + excluded.parts_lo',
    ).execute([account, currency, month, amount, ..._halves(quantity)]);
  }

  @override
  List<IntentRow> inStream(String stream, {required Position from}) => [
    for (final r in _sql(
      'SELECT i.* FROM intent_stream s JOIN intent_index i ON i.key = s.intent '
      // A range on the stream's day, so a stream is not read whole.
      'WHERE s.stream = ? AND s.date >= ? AND (s.date > ? OR s.seq >= ?) '
      'ORDER BY s.date, s.seq, i.id',
    ).select([stream, from.date.ymd, from.date.ymd, from.seq]))
      _row(r),
  ];

  @override
  List<Posting> postingsOfIntent(IntentId id) => [
    for (final r in _sql(
      'SELECT i.id AS intent_id, p.* FROM intent_index i '
      'JOIN posting p ON p.intent = i.key WHERE i.id = ? ORDER BY p.line',
    ).select([id.value]))
      _posting(r),
  ];

  @override
  List<Posting> postingsOf(AccountId account, {Position? before}) {
    final key = _keyIfAny(account);
    if (key == null) return const [];
    return [
      for (final r
          in _sql(
            'SELECT i.id AS intent_id, p.* FROM posting p '
            'JOIN intent_index i ON i.key = p.intent '
            'WHERE p.account = ? AND p.date <= ? '
            'AND (p.date < ? OR p.seq < ?) '
            'ORDER BY p.date, p.seq, i.id, p.line',
          ).select([
            key,
            before?.date.ymd ?? _end,
            before?.date.ymd ?? _end + 1,
            before?.seq ?? 0,
          ]))
        _posting(r),
    ];
  }

  @override
  List<(Day, int)> daySums(AccountId account) {
    final key = _keyIfAny(account);
    if (key == null) return const [];
    return [
      for (final r in _sql(
        'SELECT date, SUM(amount) AS amount FROM posting WHERE account = ? '
        'GROUP BY date ORDER BY date',
      ).select([key]))
        (Day.stored(r['date'] as int), r['amount'] as int),
    ];
  }

  @override
  AccountSums sums({Day? from, Day? until}) {
    final lo = from?.ymd ?? 0;
    final hi = until?.ymd ?? _end;
    final total = <(AccountId, CurrencyCode), AccountSum>{};
    // A range that ends before it starts holds nothing.
    if (lo > hi) return total;
    void add(ResultSet rows) {
      for (final r in rows) {
        final key = (
          _account(r['account'] as int),
          CurrencyCode(r['currency'] as String),
        );
        total[key] = addSums(total[key] ?? noSum, (
          amount: r['amount'] as int,
          quantity: _quantity(r),
        ));
      }
    }

    void postingsBetween(int a, int b) => add(
      _sql(
        'SELECT account, currency, SUM(amount) AS amount, '
        '$_postingQuantitySums FROM posting '
        'WHERE date BETWEEN ? AND ? GROUP BY account, currency',
      ).select([a, b]),
    );

    // Whole months come from their kept sums; a month cut by either end
    // from its postings.
    final loMonth = lo ~/ 100;
    final hiMonth = hi ~/ 100;
    final loCut = lo != 0 && lo % 100 != 1;
    final hiCut = hi != _end && Day.stored(hi).lastOfMonth.ymd != hi;
    if (loMonth == hiMonth && (loCut || hiCut)) {
      postingsBetween(lo, hi);
    } else {
      final firstWhole = loCut ? loMonth + 1 : loMonth;
      final lastWhole = hiCut ? hiMonth - 1 : hiMonth;
      if (firstWhole <= lastWhole) {
        // From the start every month is read anyway: by account, in the
        // table's own order, with nothing to sort. A span of months by
        // the month index.
        final month = lo == 0 ? '+month' : 'month';
        add(
          _sql(
            'SELECT account, currency, SUM(amount) AS amount, '
            'SUM(units_hi) AS units_hi, SUM(units_lo) AS units_lo, '
            'SUM(parts_hi) AS parts_hi, SUM(parts_lo) AS parts_lo '
            'FROM month_sum '
            'WHERE $month BETWEEN ? AND ? GROUP BY account, currency',
          ).select([firstWhole, lastWhole]),
        );
      }
      if (loCut) postingsBetween(lo, loMonth * 100 + 99);
      if (hiCut) postingsBetween(hiMonth * 100, hi);
    }
    total.removeWhere((_, s) => isNoSum(s));
    return total;
  }

  @override
  Map<(String, CurrencyCode), AccountSum> subSums(
    AccountId account, {
    Day? until,
  }) {
    final key = _keyIfAny(account);
    if (key == null) return const {};
    return {
      for (final r in _sql(
        'SELECT sub, currency, SUM(amount) AS amount, '
        '$_postingQuantitySums FROM posting WHERE account = ? '
        'AND date <= ? GROUP BY sub, currency ORDER BY MIN(date), MIN(seq), '
        'sub',
      ).select([key, until?.ymd ?? _end]))
        (r['sub'] as String, CurrencyCode(r['currency'] as String)): (
          amount: r['amount'] as int,
          quantity: _quantity(r),
        ),
    };
  }

  @override
  List<LedgerAccount> accounts() => [
    for (final r in _sql('SELECT * FROM account ORDER BY id').select())
      LedgerAccount(
        id: AccountId(r['id'] as String),
        cls: AccountClass.values.byName(r['class'] as String),
        name: r['name'] as String,
        owner: OwnerId(r['owner'] as String),
        parent: switch (r['parent']) {
          final String p => AccountId(p),
          _ => null,
        },
        currency: switch (r['currency']) {
          final String c => CurrencyCode(c),
          _ => null,
        },
        commodity: r['commodity'] as String?,
        tag: r['tag'] as String,
        inNetWorth: r['in_net_worth'] == 1,
        inFlowReports: r['in_flow_reports'] == 1,
      ),
  ];

  @override
  void keepAccounts(Iterable<LedgerAccount> accounts) {
    _sql('DELETE FROM account').execute();
    final insert = _sql(
      'INSERT INTO account (id, class, name, owner, parent, currency, '
      'commodity, tag, in_net_worth, in_flow_reports) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    );
    for (final a in accounts) {
      insert.execute([
        a.id.value,
        a.cls.name,
        a.name,
        a.owner.value,
        a.parent?.value,
        a.currency?.value,
        a.commodity,
        a.tag,
        a.inNetWorth ? 1 : 0,
        a.inFlowReports ? 1 : 0,
      ]);
    }
  }

  @override
  void clear() {
    _check();
    for (final table in [
      'posting',
      'intent_stream',
      'intent_index',
      'month_sum',
    ]) {
      _db.execute('DELETE FROM $table');
    }
    // Nothing posted is the records' own any more: never a half-built
    // journal trusted.
    _db.execute(
      "DELETE FROM meta WHERE key IN ('$_rulesKey', '$_revisionKey')",
    );
  }

  /// Begins posting the whole book afresh, in one transaction: every
  /// intent, posting and monthly sum kept is let go and the indexes are
  /// dropped, to be made again once every row is in (one sort each, in
  /// place of one insertion per row). Parts are then added as they are
  /// posted ([JournalFill.add]); [JournalFill.finish] makes the indexes
  /// and the months' sums, keeps the tree and the mark last, and commits.
  /// The commit need not wait for the disk (WAL, `synchronous=NORMAL` is
  /// safe from corruption): only derived tables are written, and a crash
  /// before they reach it loses the mark, so the book is posted afresh.
  JournalFill begin() {
    _check();
    for (final s in _statements.values) {
      s.close();
    }
    _statements.clear();
    final was = (
      cache: _db.select('PRAGMA cache_size').single.values.single,
      synchronous: _db.select('PRAGMA synchronous').single.values.single,
    );
    _db.execute('PRAGMA cache_size = $_fillCache');
    _db.execute('PRAGMA synchronous = NORMAL');
    _db.execute('BEGIN IMMEDIATE');
    try {
      for (final name in _journalIndexes.keys) {
        _db.execute('DROP INDEX IF EXISTS $name');
      }
      clear();
    } catch (_) {
      _rollBack();
      _restore(was);
      rethrow;
    }
    return JournalFill._(this, was);
  }

  /// The page cache while a whole book is written, in KiB (negative, as
  /// SQLite counts it): room for the indexes to be sorted in memory. Put
  /// back as it was once the book is in.
  static const _fillCache = -65536;

  /// Puts the connection's settings back as the store set them.
  void _restore(_Pragmas was) {
    _db.execute('PRAGMA synchronous = ${was.synchronous}');
    _db.execute('PRAGMA cache_size = ${was.cache}');
  }

  /// Writes [part], its intents numbered from [next] in the order they
  /// came, so every row lands at the end of its table; adds its postings
  /// to [months]. The next number free.
  int _add(
    FreshPostingStore part,
    Map<_MonthKey, (int, BigInt)> months,
    int next,
  ) {
    final intents = part.intents;
    final keys = <IntentId, int>{
      for (final (i, r) in intents.indexed) r.id: next + i,
    };
    _insertMany('intent_index (key, id, type, date, seq)', 5, intents.length, (
      i,
      into,
    ) {
      final r = intents[i];
      into
        ..add(next + i)
        ..add(r.id.value)
        ..add(r.type.value)
        ..add(r.date.ymd)
        ..add(r.seq);
    });
    final streams = [
      for (final r in intents)
        for (final s in r.streams) (s, r),
    ];
    _insertMany(
      'intent_stream (stream, date, seq, intent)',
      4,
      streams.length,
      (i, into) {
        final (s, r) = streams[i];
        into
          ..add(s)
          ..add(r.date.ymd)
          ..add(r.seq)
          ..add(keys[r.id]);
      },
    );
    final postings = part.postings;
    final accounts = [for (final p in postings) _accountKey(p.account)];
    final quantities = [for (final p in postings) _split(p.quantity)];
    _insertMany(
      'posting (intent, line, account, currency, amount, units, parts, '
      'sub, date, seq)',
      10,
      postings.length,
      (i, into) {
        final p = postings[i];
        into
          ..add(keys[p.intent])
          ..add(p.line)
          ..add(accounts[i])
          ..add(p.currency.value)
          ..add(p.amount)
          ..add(quantities[i].$1)
          ..add(quantities[i].$2)
          ..add(p.sub)
          ..add(p.date.ymd)
          ..add(p.seq);
      },
    );
    for (final (i, p) in postings.indexed) {
      final key = (accounts[i], p.currency.value, p.date.monthKey);
      final (amount, quantity) = months[key] ?? (0, BigInt.zero);
      months[key] = (amount + p.amount, quantity + p.quantity);
    }
    return next + intents.length;
  }

  void _finish(
    Map<_MonthKey, (int, BigInt)> months,
    List<LedgerAccount> accounts,
    JournalMark mark,
  ) {
    _journalIndexes.values.forEach(_db.execute);
    final sums = months.entries.toList()
      ..sort((a, b) {
        final byAccount = a.key.$1.compareTo(b.key.$1);
        if (byAccount != 0) return byAccount;
        final byCurrency = a.key.$2.compareTo(b.key.$2);
        return byCurrency != 0 ? byCurrency : a.key.$3.compareTo(b.key.$3);
      });
    _insertMany(
      'month_sum (account, currency, month, amount, units_hi, units_lo, '
      'parts_hi, parts_lo)',
      8,
      sums.length,
      (i, into) {
        final MapEntry(key: (account, currency, month), value: (a, q)) =
            sums[i];
        into
          ..add(account)
          ..add(currency)
          ..add(month)
          ..add(a)
          ..addAll(_halves(q));
      },
    );
    keepAccounts(accounts);
    keepMark(mark);
    _db.execute('COMMIT');
  }

  /// How many rows one INSERT statement carries when a whole book is
  /// written: far under SQLite's limit of 32,766 values a statement.
  static const _rowsPerInsert = 500;

  /// Inserts [count] rows of [width] values into [into], each row's values
  /// added by [row], [_rowsPerInsert] rows a statement.
  void _insertMany(
    String into,
    int width,
    int count,
    void Function(int i, List<Object?> values) row,
  ) {
    final one = '(${List.filled(width, '?').join(', ')})';
    String sql(int rows) =>
        'INSERT INTO $into VALUES ${List.filled(rows, one).join(', ')}';
    final full = _sql(sql(_rowsPerInsert));
    final values = <Object?>[];
    var i = 0;
    for (; i + _rowsPerInsert <= count; i += _rowsPerInsert) {
      values.clear();
      for (var k = i; k < i + _rowsPerInsert; k++) {
        row(k, values);
      }
      full.execute(values);
    }
    if (i < count) {
      values.clear();
      for (var k = i; k < count; k++) {
        row(k, values);
      }
      final last = _db.prepare(sql(count - i));
      try {
        last.execute(values);
      } finally {
        last.close();
      }
    }
  }

  /// A quantity as its whole units and its parts, each of the same sign:
  /// what a row keeps.
  static (int, int) _split(BigInt quantity) {
    if (!keepable(quantity)) {
      throw ArgumentError.value(quantity, 'quantity', 'more than is kept');
    }
    return (
      (quantity ~/ quantityScale).toInt(),
      quantity.remainder(quantityScale).toInt(),
    );
  }

  /// The halves of [quantity] a month's sum keeps: its whole units' high
  /// bits and low 32, then its parts' (each the same sign as [quantity]).
  /// The low halves are never negative, so adding them up stays exact.
  static List<int> _halves(BigInt quantity) {
    final whole = quantity ~/ quantityScale;
    final parts = quantity.remainder(quantityScale);
    return [
      (whole >> 32).toInt(),
      (whole & _low32).toInt(),
      (parts >> 32).toInt(),
      (parts & _low32).toInt(),
    ];
  }

  static final _low32 = BigInt.from(0xFFFFFFFF);

  /// The sums of the postings' quantities in halves, as [_quantity] reads
  /// them: SQL's SUM of the `units` column itself would overflow past
  /// 2^63 units (r14 F6); a sum of halves would only past 2^31 rows.
  static const _postingQuantitySums =
      'SUM(units >> 32) AS units_hi, SUM(units & 4294967295) AS units_lo, '
      'SUM(parts >> 32) AS parts_hi, SUM(parts & 4294967295) AS parts_lo';

  /// The quantity a sum of rows keeps in halves ([_halves]).
  static BigInt _quantity(Row r) {
    BigInt joined(String column) =>
        (BigInt.from(r['${column}_hi'] as int) << 32) +
        BigInt.from(r['${column}_lo'] as int);
    return joined('units') * quantityScale + joined('parts');
  }

  @override
  int get intentCount =>
      _sql('SELECT count(*) AS n FROM intent_index').select().single['n']
          as int;

  @override
  int get postingCount =>
      _sql('SELECT count(*) AS n FROM posting').select().single['n'] as int;
}
