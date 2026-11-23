import 'package:kernel/kernel.dart';
import 'package:sqlite3/sqlite3.dart';

/// Layout version 1 to 2: the journal's tables beside the records. All
/// of them are derived from the records (`rows`): they can be dropped
/// and posted again, a backup does not carry them, and a record set
/// aside has no postings. The body of an intent stays in its row.
void createJournalTables(Database db) {
  db.execute('''
    CREATE TABLE account (
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
    CREATE TABLE intent_index (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      date INTEGER NOT NULL,
      seq INTEGER NOT NULL
    ) STRICT, WITHOUT ROWID
  ''');
  db.execute('''
    CREATE TABLE intent_stream (
      stream TEXT NOT NULL,
      date INTEGER NOT NULL,
      seq INTEGER NOT NULL,
      intent_id TEXT NOT NULL,
      PRIMARY KEY (stream, date, seq, intent_id)
    ) STRICT, WITHOUT ROWID
  ''');
  db.execute('CREATE INDEX intent_stream_intent ON intent_stream (intent_id)');
  db.execute('''
    CREATE TABLE posting (
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
  // Kept in the order written (rowid), so posting a whole book appends;
  // an intent's lines are found by the first index.
  db.execute('CREATE UNIQUE INDEX posting_line ON posting (intent_id, line)');
  // A period's sums read this index alone; one account's history in
  // book order the second.
  db.execute(
    'CREATE INDEX posting_date '
    'ON posting (date, account, currency, amount, quantity)',
  );
  db.execute('CREATE INDEX posting_account ON posting (account, date, seq)');
  // Each month's sum by account, kept in the same transaction as the
  // postings: every balance is the months before plus this month's.
  db.execute('''
    CREATE TABLE month_sum (
      account TEXT NOT NULL,
      currency TEXT NOT NULL,
      month INTEGER NOT NULL,
      amount INTEGER NOT NULL,
      quantity INTEGER NOT NULL,
      PRIMARY KEY (account, currency, month)
    ) STRICT, WITHOUT ROWID
  ''');
  db.execute(
    'CREATE INDEX month_sum_month '
    'ON month_sum (month, account, currency, amount, quantity)',
  );
}

/// The journal's [PostingStore] on the ledger's own file.
final class SqlPostingStore implements PostingStore {
  SqlPostingStore(this._db);

  final Database _db;
  var _inTransaction = false;
  final _statements = <String, PreparedStatement>{};

  /// The meta keys the mark is kept under.
  static const _rulesKey = 'journal.rules';
  static const _revisionKey = 'journal.revision';

  /// Past the last day any book holds.
  static const _end = 99991231;

  PreparedStatement _sql(String sql) =>
      _statements[sql] ??= _db.prepare(sql, persistent: true);

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
        add(
          _sql(
            'SELECT account, currency, SUM(amount) AS amount, '
            'SUM(quantity) AS quantity FROM month_sum '
            'WHERE month BETWEEN ? AND ? GROUP BY account, currency',
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
    for (final table in [
      'posting',
      'intent_stream',
      'intent_index',
      'month_sum',
    ]) {
      _db.execute('DELETE FROM $table');
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
