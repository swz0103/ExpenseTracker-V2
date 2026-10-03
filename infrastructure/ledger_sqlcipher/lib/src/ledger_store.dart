import 'dart:convert';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';

/// Projection tables. Released steps are never edited; add a new step.
final ledgerSchema = SchemaModule('ledger', [
  [
    '''
    CREATE TABLE ledger_accounts (
      id TEXT PRIMARY KEY,
      workspace TEXT NOT NULL,
      state TEXT NOT NULL,
      payload TEXT NOT NULL
    ) STRICT, WITHOUT ROWID
    ''',
    'CREATE INDEX ledger_accounts_by_workspace ON ledger_accounts (workspace)',
    '''
    CREATE TABLE ledger_postings (
      id TEXT PRIMARY KEY,
      workspace TEXT NOT NULL,
      kind TEXT NOT NULL,
      date TEXT NOT NULL,
      payload TEXT NOT NULL,
      reversal_of TEXT UNIQUE REFERENCES ledger_postings (id)
    ) STRICT, WITHOUT ROWID
    ''',
    'CREATE INDEX ledger_postings_by_date ON ledger_postings (workspace, date)',
    '''
    CREATE TABLE ledger_legs (
      posting_id TEXT NOT NULL REFERENCES ledger_postings (id),
      leg INTEGER NOT NULL,
      account_id TEXT NOT NULL REFERENCES ledger_accounts (id),
      minor_units TEXT NOT NULL,
      PRIMARY KEY (posting_id, leg)
    ) STRICT, WITHOUT ROWID
    ''',
    'CREATE INDEX ledger_legs_by_account ON ledger_legs (account_id)',
    '''
    CREATE TABLE ledger_balances (
      account_id TEXT PRIMARY KEY REFERENCES ledger_accounts (id),
      minor_units TEXT NOT NULL
    ) STRICT, WITHOUT ROWID
    ''',
    '''
    CREATE TABLE ledger_monthly (
      workspace TEXT NOT NULL,
      month TEXT NOT NULL,
      currency TEXT NOT NULL,
      scale INTEGER NOT NULL,
      income TEXT NOT NULL,
      expense TEXT NOT NULL,
      PRIMARY KEY (workspace, month, currency, scale)
    ) STRICT, WITHOUT ROWID
    ''',
    '''
    CREATE TRIGGER ledger_postings_immutable BEFORE UPDATE ON ledger_postings
    BEGIN SELECT RAISE(ABORT, 'postings are immutable'); END
    ''',
    '''
    CREATE TRIGGER ledger_postings_kept BEFORE DELETE ON ledger_postings
    BEGIN SELECT RAISE(ABORT, 'postings are immutable'); END
    ''',
  ],
]);

/// Income and expense for one month in one currency, as reported totals.
final class MonthlyTotal {
  const MonthlyTotal(this.income, this.expense);

  final Money income;
  final Money expense;
}

/// Bookkeeping on one SQLCipher store. Open the store with [ledgerSchema].
final class LedgerStore implements UnitOfWork<SqlBookkeeping> {
  LedgerStore(this._store) {
    if (_store.moduleVersion(ledgerSchema.name) !=
        ledgerSchema.migrations.length) {
      throw StateError('Open the store with ledgerSchema.');
    }
  }

  final SqlCipherStore _store;

  @override
  Future<R> write<R>(Future<R> Function(SqlBookkeeping transaction) body) =>
      _store.write((transaction) => body(SqlBookkeeping._(transaction)));

  List<Account> accounts(WorkspaceId workspace) {
    final rows = _store.select(
      'SELECT payload FROM ledger_accounts WHERE workspace = ? ORDER BY id',
      [workspace.toString()],
    );
    return [for (final row in rows) _decodeAccount(row['payload'])];
  }

  Money balance(Account account) {
    final rows = _store.select(
      'SELECT minor_units FROM ledger_balances WHERE account_id = ?',
      [account.id.value],
    );
    return _balance(account.currency, rows);
  }

  /// Every posting that touches [accountId], oldest first.
  List<Posting> postings(PublicId accountId) {
    final rows = _store.select(
      'SELECT p.payload FROM ledger_postings p '
      'WHERE p.id IN (SELECT posting_id FROM ledger_legs WHERE account_id = ?) '
      'ORDER BY p.date, p.id',
      [accountId.value],
    );
    return [for (final row in rows) _decodePosting(row['payload'])];
  }

  /// Totals for `YYYY-MM`, keyed by currency code.
  Map<String, MonthlyTotal> monthly(WorkspaceId workspace, String month) {
    final rows = _store.select(
      'SELECT * FROM ledger_monthly WHERE workspace = ? AND month = ?',
      [workspace.toString(), month],
    );
    return {
      for (final row in rows)
        row['currency'] as String: MonthlyTotal(
          _money(row, 'income'),
          _money(row, 'expense'),
        ),
    };
  }
}

/// The bookkeeping port on a SQLCipher write transaction. Every projection
/// change happens in the same transaction as the event.
final class SqlBookkeeping implements BookkeepingTransaction {
  SqlBookkeeping._(this._transaction);

  final SqlTransaction _transaction;

  @override
  Future<RecordedOperation?> findOperation(OperationKey key) =>
      _transaction.findOperation(key);

  @override
  Future<void> recordOperation(RecordedOperation operation) =>
      _transaction.recordOperation(operation);

  @override
  Future<void> enqueue(OutboxMessage message) => _transaction.enqueue(message);

  @override
  Future<void> appendEvent({
    required PublicId id,
    required WorkspaceId workspace,
    required String kind,
    required String payload,
  }) async {
    _transaction.append(
      id: id,
      workspace: workspace,
      kind: kind,
      payload: payload,
    );
  }

  @override
  Future<Account?> account(PublicId id) async {
    final rows = _transaction.select(
      'SELECT payload FROM ledger_accounts WHERE id = ?',
      [id.value],
    );
    return rows.isEmpty ? null : _decodeAccount(rows.single['payload']);
  }

  @override
  Future<Posting?> posting(PublicId id) async {
    final rows = _transaction.select(
      'SELECT payload FROM ledger_postings WHERE id = ?',
      [id.value],
    );
    return rows.isEmpty ? null : _decodePosting(rows.single['payload']);
  }

  @override
  Future<bool> isReversed(PublicId postingId) async {
    final rows = _transaction.select(
      'SELECT 1 FROM ledger_postings WHERE reversal_of = ?',
      [postingId.value],
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> saveAccount(Account account) async {
    _transaction.execute(
      'INSERT INTO ledger_accounts (id, workspace, state, payload) '
      'VALUES (?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET '
      'state = excluded.state, payload = excluded.payload',
      [
        account.id.value,
        account.workspace.toString(),
        account.state.name,
        jsonEncode(AccountCodec.encode(account)),
      ],
    );
  }

  @override
  Future<void> savePosting(Posting posting) async {
    _transaction.execute(
      'INSERT INTO ledger_postings '
      '(id, workspace, kind, date, payload, reversal_of) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        posting.id.value,
        posting.operation.workspace.toString(),
        posting.kind.name,
        posting.date.toString(),
        jsonEncode(PostingCodec.encode(posting)),
        posting.reversalOf?.value,
      ],
    );
    for (var i = 0; i < posting.legs.length; i++) {
      final leg = posting.legs[i];
      _transaction.execute('INSERT INTO ledger_legs VALUES (?, ?, ?, ?)', [
        posting.id.value,
        i,
        leg.account.id.value,
        '${leg.amount.minorUnits}',
      ]);
      _addToBalance(leg.account.id, leg.amount);
    }
    _addToMonth(posting);
  }

  void _addToBalance(PublicId accountId, Money amount) {
    final rows = _transaction.select(
      'SELECT minor_units FROM ledger_balances WHERE account_id = ?',
      [accountId.value],
    );
    final next = _balance(amount.currency, rows) + amount;
    _transaction.execute(
      'INSERT INTO ledger_balances VALUES (?, ?) ON CONFLICT (account_id) '
      'DO UPDATE SET minor_units = excluded.minor_units',
      [accountId.value, '${next.minorUnits}'],
    );
  }

  void _addToMonth(Posting posting) {
    final income = posting.reportIncome;
    final expense = posting.reportExpense;
    if (income.minorUnits == BigInt.zero && expense.minorUnits == BigInt.zero) {
      return;
    }
    final key = [
      posting.operation.workspace.toString(),
      posting.date.toString().substring(0, 7),
      income.currency.code,
      income.currency.scale,
    ];
    final rows = _transaction.select(
      'SELECT * FROM ledger_monthly '
      'WHERE workspace = ? AND month = ? AND currency = ? AND scale = ?',
      key,
    );
    var total = MonthlyTotal(income, expense);
    if (rows.isNotEmpty) {
      total = MonthlyTotal(
        _money(rows.single, 'income') + income,
        _money(rows.single, 'expense') + expense,
      );
    }
    _transaction.execute(
      'INSERT INTO ledger_monthly VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (workspace, month, currency, scale) DO UPDATE SET '
      'income = excluded.income, expense = excluded.expense',
      [...key, '${total.income.minorUnits}', '${total.expense.minorUnits}'],
    );
  }
}

Account _decodeAccount(Object? payload) =>
    AccountCodec.decode(jsonDecode(payload as String) as Map<String, Object?>);

Posting _decodePosting(Object? payload) =>
    PostingCodec.decode(jsonDecode(payload as String) as Map<String, Object?>);

Money _balance(Currency currency, List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return Money(currency, BigInt.zero);
  return Money(currency, parseMinorUnits(rows.single['minor_units'] as String));
}

Money _money(Map<String, Object?> row, String column) => Money(
  Currency(row['currency'] as String, row['scale'] as int),
  parseMinorUnits(row[column] as String),
);
