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
void createJournalTables(Database db) {
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
  db.execute('''
    CREATE TABLE IF NOT EXISTS intent_index (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      date INTEGER NOT NULL,
      seq INTEGER NOT NULL
    ) STRICT, WITHOUT ROWID
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS intent_stream (
      stream TEXT NOT NULL,
      date INTEGER NOT NULL,
      seq INTEGER NOT NULL,
      intent_id TEXT NOT NULL,
      PRIMARY KEY (stream, date, seq, intent_id)
    ) STRICT, WITHOUT ROWID
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS posting (
      intent_id TEXT NOT NULL,
      line INTEGER NOT NULL,
      account TEXT NOT NULL,
      currency TEXT NOT NULL,
      amount INTEGER NOT NULL,
      quantity INTEGER NOT NULL,
      sub TEXT NOT NULL,
      date INTEGER NOT NULL,
      seq INTEGER NOT NULL
    ) STRICT
  ''');
  // Each month's sum by account, kept in the same transaction as the
  // postings: every balance is the months before plus this month's.
  db.execute('''
    CREATE TABLE IF NOT EXISTS month_sum (
      account TEXT NOT NULL,
      currency TEXT NOT NULL,
      month INTEGER NOT NULL,
      amount INTEGER NOT NULL,
      quantity INTEGER NOT NULL,
      PRIMARY KEY (account, currency, month)
    ) STRICT, WITHOUT ROWID
  ''');
  _journalIndexes.values.forEach(db.execute);
}

/// The journal's indexes, by name. Posting a whole book afresh drops
/// them and makes them again once every row is in ([SqlPostingStore.fill]):
/// one sort each, in place of one insertion per row.
const _journalIndexes = {
  // A period's whole months are read by month.
  'month_sum_month':
      'CREATE INDEX IF NOT EXISTS month_sum_month '
      'ON month_sum (month, account, currency, amount, quantity)',
  // The posting table is kept in the order written (rowid); an intent's
  // lines are found by this index.
  'posting_line':
      'CREATE UNIQUE INDEX IF NOT EXISTS posting_line '
      'ON posting (intent_id, line)',
  'intent_stream_intent':
      'CREATE INDEX IF NOT EXISTS intent_stream_intent '
      'ON intent_stream (intent_id)',
  // The days of a month cut by a period's end are read through this.
  'posting_date': 'CREATE INDEX IF NOT EXISTS posting_date ON posting (date)',
  // One account's history in book order.
  'posting_account':
      'CREATE INDEX IF NOT EXISTS posting_account '
      'ON posting (account, date, seq)',
};

/// The connection's settings a fill changes for its own transaction.
typedef _Pragmas = ({Object? cache, Object? synchronous});

/// A record as kept: its shelf, its id there, its place, its body.
typedef KeptRow = ({String shelf, String id, int seq, String body});

/// Posting a whole book afresh, under way in one transaction
/// ([SqlPostingStore.begin]): parts added as they are posted, then
/// finished, or abandoned with nothing changed.
final class JournalFill {
  JournalFill._(this._store, this._was);

  final SqlPostingStore _store;
  final _Pragmas _was;
  final _months = <(String, String, int), (int, int)>{};
  var _done = false;

  /// Writes the intents and postings of [part].
  void add(FreshPostingStore part) {
    if (_done) throw StateError('fill done');
    _store._add(part, _months);
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

  /// The meta keys the mark is kept under.
  static const _rulesKey = 'journal.rules';
  static const _revisionKey = 'journal.revision';

  /// Past the last day any book holds.
  static const _end = 99991231;

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
  }

  /// Lets the prepared statements go, before the file is closed.
  void close() {
    for (final s in _statements.values) {
      s.close();
    }
    _statements.clear();
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
      if (!_db.autocommit) _db.execute('ROLLBACK');
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
        'SELECT stream FROM intent_stream WHERE intent_id = ? ORDER BY stream',
      ).select([r['id']]))
        s['stream'] as String,
    ],
  );

  static Posting _posting(Row r) => Posting(
    intent: IntentId(r['intent_id'] as String),
    line: r['line'] as int,
    account: AccountId(r['account'] as String),
    amount: r['amount'] as int,
    currency: CurrencyCode(r['currency'] as String),
    date: Day.stored(r['date'] as int),
    seq: r['seq'] as int,
    quantity: r['quantity'] as int,
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
    final index = [row.id.value, row.type.value, row.date.ymd, row.seq];
    _sql(
      'INSERT OR IGNORE INTO intent_index (id, type, date, seq) '
      'VALUES (?, ?, ?, ?)',
    ).execute(index);
    if (_db.updatedRows == 0) {
      // Kept before: what it had goes first. A new one, as when the whole
      // book is posted afresh, has nothing to take away.
      remove(row.id);
      _sql('INSERT INTO intent_index (id, type, date, seq) VALUES (?, ?, ?, ?)')
          .execute(index);
    }
    final stream = _sql(
      'INSERT OR IGNORE INTO intent_stream (stream, date, seq, intent_id) '
      'VALUES (?, ?, ?, ?)',
    );
    for (final s in row.streams) {
      stream.execute([s, row.date.ymd, row.seq, row.id.value]);
    }
    final insert = _sql(
      'INSERT INTO posting (intent_id, line, account, currency, amount, '
      'quantity, sub, date, seq) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    );
    final months = <(String, String, int), (int, int)>{};
    for (final p in postings) {
      insert.execute([
        row.id.value,
        p.line,
        p.account.value,
        p.currency.value,
        p.amount,
        p.quantity,
        p.sub,
        p.date.ymd,
        row.seq,
      ]);
      final key = (p.account.value, p.currency.value, p.date.monthKey);
      final (amount, quantity) = months[key] ?? (0, 0);
      months[key] = (amount + p.amount, quantity + p.quantity);
    }
    for (final MapEntry(key: (account, currency, month), value: (a, q))
        in months.entries) {
      _addToMonth(account, currency, month, a, q);
    }
  }

  @override
  void remove(IntentId id) {
    for (final r in _sql(
      'SELECT account, currency, date / 100 AS month, SUM(amount) AS amount, '
      'SUM(quantity) AS quantity FROM posting WHERE intent_id = ? '
      'GROUP BY account, currency, month',
    ).select([id.value])) {
      _addToMonth(
        r['account'] as String,
        r['currency'] as String,
        r['month'] as int,
        -(r['amount'] as int),
        -(r['quantity'] as int),
      );
    }
    _sql('DELETE FROM posting WHERE intent_id = ?').execute([id.value]);
    _sql('DELETE FROM intent_stream WHERE intent_id = ?').execute([id.value]);
    _sql('DELETE FROM intent_index WHERE id = ?').execute([id.value]);
  }

  void _addToMonth(
    String account,
    String currency,
    int month,
    int amount,
    int quantity,
  ) {
    _sql(
      'INSERT INTO month_sum (account, currency, month, amount, quantity) '
      'VALUES (?, ?, ?, ?, ?) ON CONFLICT (account, currency, month) '
      'DO UPDATE SET amount = amount + excluded.amount, '
      'quantity = quantity + excluded.quantity',
    ).execute([account, currency, month, amount, quantity]);
  }

  @override
  List<IntentRow> inStream(String stream, {required Position from}) => [
    for (final r in _sql(
      'SELECT i.* FROM intent_stream s JOIN intent_index i ON i.id = s.intent_id '
      // A range on the index's day, so a stream is not read whole.
      'WHERE s.stream = ? AND s.date >= ? AND (s.date > ? OR s.seq >= ?) '
      'ORDER BY s.date, s.seq, s.intent_id',
    ).select([stream, from.date.ymd, from.date.ymd, from.seq]))
      _row(r),
  ];

  @override
  List<Posting> postingsOfIntent(IntentId id) => [
    for (final r in _sql(
      'SELECT * FROM posting WHERE intent_id = ? ORDER BY line',
    ).select([id.value]))
      _posting(r),
  ];

  @override
  List<Posting> postingsOf(AccountId account, {Position? before}) => [
    for (final r
        in _sql(
          'SELECT * FROM posting WHERE account = ? AND date <= ? '
          'AND (date < ? OR seq < ?) ORDER BY date, seq, intent_id, line',
        ).select([
          account.value,
          before?.date.ymd ?? _end,
          before?.date.ymd ?? _end + 1,
          before?.seq ?? 0,
        ]))
      _posting(r),
  ];

  @override
  AccountSums sums({Day? from, Day? until}) {
    final lo = from?.ymd ?? 0;
    final hi = until?.ymd ?? _end;
    final total = <(AccountId, CurrencyCode), AccountSum>{};
    void add(ResultSet rows) {
      for (final r in rows) {
        final key = (
          AccountId(r['account'] as String),
          CurrencyCode(r['currency'] as String),
        );
        total[key] = addSums(total[key] ?? (amount: 0, quantity: 0), (
          amount: r['amount'] as int,
          quantity: r['quantity'] as int,
        ));
      }
    }

    void postingsBetween(int a, int b) => add(
      _sql(
        'SELECT account, currency, SUM(amount) AS amount, '
        'SUM(quantity) AS quantity FROM posting WHERE date BETWEEN ? AND ? '
        'GROUP BY account, currency',
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
            'SUM(quantity) AS quantity FROM month_sum '
            'WHERE $month BETWEEN ? AND ? GROUP BY account, currency',
          ).select([firstWhole, lastWhole]),
        );
      }
      if (loCut) postingsBetween(lo, loMonth * 100 + 99);
      if (hiCut) postingsBetween(hiMonth * 100, hi);
    }
    total.removeWhere((_, s) => s.amount == 0 && s.quantity == 0);
    return total;
  }

  @override
  Map<(String, CurrencyCode), AccountSum> subSums(
    AccountId account, {
    Day? until,
  }) => {
    for (final r in _sql(
      'SELECT sub, currency, SUM(amount) AS amount, SUM(quantity) AS quantity '
      'FROM posting WHERE account = ? AND date <= ? GROUP BY sub, currency '
      'ORDER BY MIN(date), MIN(seq), sub',
    ).select([account.value, until?.ymd ?? _end]))
      (r['sub'] as String, CurrencyCode(r['currency'] as String)): (
        amount: r['amount'] as int,
        quantity: r['quantity'] as int,
      ),
  };

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
      _db.execute('ROLLBACK');
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

  void _add(
    FreshPostingStore part,
    Map<(String, String, int), (int, int)> months,
  ) {
    // In the order of the key, so each row lands at the end of its tree.
    final intents = [...part.intents]
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    _insertMany('intent_index (id, type, date, seq)', 4, intents.length, (
      i,
      into,
    ) {
      final r = intents[i];
      into
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
      'intent_stream (stream, date, seq, intent_id)',
      4,
      streams.length,
      (i, into) {
        final (s, r) = streams[i];
        into
          ..add(s)
          ..add(r.date.ymd)
          ..add(r.seq)
          ..add(r.id.value);
      },
    );
    final postings = part.postings;
    _insertMany(
      'posting (intent_id, line, account, currency, amount, quantity, sub, '
      'date, seq)',
      9,
      postings.length,
      (i, into) {
        final p = postings[i];
        into
          ..add(p.intent.value)
          ..add(p.line)
          ..add(p.account.value)
          ..add(p.currency.value)
          ..add(p.amount)
          ..add(p.quantity)
          ..add(p.sub)
          ..add(p.date.ymd)
          ..add(p.seq);
      },
    );
    for (final p in postings) {
      final key = (p.account.value, p.currency.value, p.date.monthKey);
      final (amount, quantity) = months[key] ?? (0, 0);
      months[key] = (amount + p.amount, quantity + p.quantity);
    }
  }

  void _finish(
    Map<(String, String, int), (int, int)> months,
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
      'month_sum (account, currency, month, amount, quantity)',
      5,
      sums.length,
      (i, into) {
        final MapEntry(key: (account, currency, month), value: (a, q)) =
            sums[i];
        into
          ..add(account)
          ..add(currency)
          ..add(month)
          ..add(a)
          ..add(q);
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
    final full = _db.prepare(sql(_rowsPerInsert));
    try {
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
    } finally {
      full.close();
    }
  }

  @override
  int get intentCount =>
      _sql('SELECT count(*) AS n FROM intent_index').select().single['n']
          as int;

  @override
  int get postingCount =>
      _sql('SELECT count(*) AS n FROM posting').select().single['n'] as int;
}
