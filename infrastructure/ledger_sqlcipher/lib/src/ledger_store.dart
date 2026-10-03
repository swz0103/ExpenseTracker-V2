import 'dart:convert';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:budgets/budgets.dart';
import 'package:categories/categories.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';
import 'package:merchants/merchants.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:reports/reports.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:tags/tags.dart';

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
  [
    '''
    CREATE TABLE catalog_entries (
      type TEXT NOT NULL,
      id TEXT NOT NULL,
      workspace TEXT NOT NULL,
      payload TEXT NOT NULL,
      PRIMARY KEY (type, id)
    ) STRICT, WITHOUT ROWID
    ''',
    'CREATE INDEX catalog_by_workspace ON catalog_entries (workspace, type)',
    '''
    CREATE TABLE ledger_posting_tags (
      posting_id TEXT NOT NULL REFERENCES ledger_postings (id),
      tag_id TEXT NOT NULL,
      PRIMARY KEY (posting_id, tag_id)
    ) STRICT, WITHOUT ROWID
    ''',
    'CREATE INDEX ledger_posting_tags_by_tag ON ledger_posting_tags (tag_id)',
    '''
    CREATE TABLE ledger_posting_merchants (
      posting_id TEXT PRIMARY KEY REFERENCES ledger_postings (id),
      merchant_id TEXT NOT NULL
    ) STRICT, WITHOUT ROWID
    ''',
    '''
    CREATE INDEX ledger_posting_merchants_by_merchant
    ON ledger_posting_merchants (merchant_id)
    ''',
    '''
    CREATE TABLE ledger_category_monthly (
      workspace TEXT NOT NULL,
      month TEXT NOT NULL,
      category_id TEXT NOT NULL,
      currency TEXT NOT NULL,
      scale INTEGER NOT NULL,
      income TEXT NOT NULL,
      expense TEXT NOT NULL,
      PRIMARY KEY (workspace, month, category_id, currency, scale)
    ) STRICT, WITHOUT ROWID
    ''',
  ],
  [
    '''
    CREATE TABLE card_terms (
      card_id TEXT PRIMARY KEY REFERENCES ledger_accounts (id),
      payload TEXT NOT NULL
    ) STRICT, WITHOUT ROWID
    ''',
    '''
    CREATE TABLE card_charges (
      id TEXT PRIMARY KEY,
      card_id TEXT NOT NULL REFERENCES ledger_accounts (id),
      posting_id TEXT UNIQUE REFERENCES ledger_postings (id),
      payload TEXT NOT NULL
    ) STRICT, WITHOUT ROWID
    ''',
    'CREATE INDEX card_charges_by_card ON card_charges (card_id)',
    '''
    CREATE TABLE card_payments (
      id TEXT PRIMARY KEY,
      card_id TEXT NOT NULL REFERENCES ledger_accounts (id),
      posting_id TEXT NOT NULL UNIQUE REFERENCES ledger_postings (id),
      payload TEXT NOT NULL
    ) STRICT, WITHOUT ROWID
    ''',
    'CREATE INDEX card_payments_by_card ON card_payments (card_id)',
    '''
    CREATE TABLE card_installment_plans (
      purchase_posting_id TEXT PRIMARY KEY REFERENCES ledger_postings (id),
      card_id TEXT NOT NULL REFERENCES ledger_accounts (id),
      payload TEXT NOT NULL
    ) STRICT, WITHOUT ROWID
    ''',
  ],
  [
    '''
    CREATE TABLE invest_registry (
      type TEXT NOT NULL,
      id TEXT NOT NULL,
      payload TEXT NOT NULL,
      PRIMARY KEY (type, id)
    ) STRICT, WITHOUT ROWID
    ''',
    '''
    CREATE TABLE invest_listings (
      market TEXT NOT NULL,
      symbol TEXT NOT NULL,
      instrument_id TEXT NOT NULL UNIQUE,
      PRIMARY KEY (market, symbol)
    ) STRICT, WITHOUT ROWID
    ''',
    '''
    CREATE TABLE invest_trades (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      account_id TEXT NOT NULL,
      instrument_id TEXT NOT NULL,
      posting_id TEXT NOT NULL UNIQUE REFERENCES ledger_postings (id),
      payload TEXT NOT NULL
    ) STRICT
    ''',
    '''
    CREATE INDEX invest_trades_by_holding
    ON invest_trades (account_id, instrument_id, seq)
    ''',
    '''
    CREATE TRIGGER invest_trades_immutable BEFORE UPDATE ON invest_trades
    BEGIN SELECT RAISE(ABORT, 'trades are immutable'); END
    ''',
    '''
    CREATE TRIGGER invest_trades_kept BEFORE DELETE ON invest_trades
    BEGIN SELECT RAISE(ABORT, 'trades are immutable'); END
    ''',
  ],
  [
    '''
    ALTER TABLE ledger_postings
    ADD COLUMN refund_of TEXT REFERENCES ledger_postings (id)
    ''',
    'CREATE INDEX ledger_postings_by_refund ON ledger_postings (refund_of)',
  ],
  [
    '''
    CREATE TABLE ledger_notes (
      posting_id TEXT PRIMARY KEY REFERENCES ledger_postings (id),
      revision INTEGER NOT NULL,
      text TEXT NOT NULL
    ) STRICT, WITHOUT ROWID
    ''',
  ],
  [
    '''
    CREATE TABLE plan_budgets (
      id TEXT PRIMARY KEY,
      workspace TEXT NOT NULL,
      month TEXT NOT NULL,
      payload TEXT NOT NULL
    ) STRICT, WITHOUT ROWID
    ''',
    'CREATE INDEX plan_budgets_by_month ON plan_budgets (workspace, month)',
    '''
    CREATE TABLE plan_recurring (
      id TEXT PRIMARY KEY,
      workspace TEXT NOT NULL,
      active INTEGER NOT NULL,
      payload TEXT NOT NULL
    ) STRICT, WITHOUT ROWID
    ''',
    '''
    CREATE TABLE plan_recurring_confirmed (
      template_id TEXT NOT NULL REFERENCES plan_recurring (id),
      due_date TEXT NOT NULL,
      posting_id TEXT NOT NULL UNIQUE REFERENCES ledger_postings (id),
      PRIMARY KEY (template_id, due_date)
    ) STRICT, WITHOUT ROWID
    ''',
  ],
  [
    // A stock split is a trade with no cash posting, so posting_id becomes
    // optional. SQLite cannot relax NOT NULL in place; the table is
    // rebuilt with the same rows and sequence numbers.
    'DROP TRIGGER invest_trades_immutable',
    'DROP TRIGGER invest_trades_kept',
    '''
    CREATE TABLE invest_trades_next (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      account_id TEXT NOT NULL,
      instrument_id TEXT NOT NULL,
      posting_id TEXT UNIQUE REFERENCES ledger_postings (id),
      payload TEXT NOT NULL
    ) STRICT
    ''',
    'INSERT INTO invest_trades_next SELECT * FROM invest_trades',
    'DROP TABLE invest_trades',
    'ALTER TABLE invest_trades_next RENAME TO invest_trades',
    '''
    CREATE INDEX invest_trades_by_holding
    ON invest_trades (account_id, instrument_id, seq)
    ''',
    '''
    CREATE TRIGGER invest_trades_immutable BEFORE UPDATE ON invest_trades
    BEGIN SELECT RAISE(ABORT, 'trades are immutable'); END
    ''',
    '''
    CREATE TRIGGER invest_trades_kept BEFORE DELETE ON invest_trades
    BEGIN SELECT RAISE(ABORT, 'trades are immutable'); END
    ''',
    '''
    ALTER TABLE card_charges
    ADD COLUMN released INTEGER NOT NULL DEFAULT 0
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

  /// The underlying store, for journal-level work such as backups.
  SqlCipherStore get store => _store;

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

  List<Category> categories(WorkspaceId workspace) => [
    for (final json in _catalog('category', workspace))
      CatalogCodec.readCategory(json),
  ];

  List<Tag> tags(WorkspaceId workspace) => [
    for (final json in _catalog('tag', workspace)) CatalogCodec.readTag(json),
  ];

  List<Merchant> merchants(WorkspaceId workspace) => [
    for (final json in _catalog('merchant', workspace))
      CatalogCodec.readMerchant(json),
  ];

  CreditCardTerms? cardTerms(PublicId cardId) =>
      _readTerms(_store.select, cardId);

  /// The statement whose cycle contains [date], from posted charges and
  /// payments. Pending authorizations are only counted.
  CardStatement statement(PublicId cardId, BusinessDate date) {
    final terms = cardTerms(cardId);
    if (terms == null) throw StateError('Card has no terms.');
    final charges = _store.select(
      'SELECT payload FROM card_charges WHERE card_id = ? AND released = 0',
      [cardId.value],
    );
    final payments = _store.select(
      'SELECT payload FROM card_payments WHERE card_id = ?',
      [cardId.value],
    );
    return CardStatement.calculate(
      terms: terms,
      cycle: terms.scheduledCycleFor(date),
      charges: [
        for (final row in charges)
          CardRecords.readCharge(_json(row['payload'])),
      ],
      payments: [
        for (final row in payments)
          CardRecords.readPayment(_json(row['payload'])),
      ],
    );
  }

  /// Forecast installments for the purchase posted as [postingId].
  List<CardInstallment> installments(PublicId postingId) {
    final plan = _readPlan(_store.select, postingId);
    return plan == null ? const [] : plan.installments;
  }

  /// Open lots for one investment account and instrument, replayed from
  /// its trades.
  List<InvestmentHoldingLot> holdings(
    PublicId accountId,
    PublicId instrumentId,
  ) => InvestmentRecords.openLots(
    _readTrades(_store.select, accountId, instrumentId),
  );

  EntryNote note(PublicId postingId) => _readNote(_store.select, postingId);

  /// Report facts for one month, in date order: the same facts monthly
  /// reports and budgets use.
  List<MonthlyFact> monthlyFacts(WorkspaceId workspace, ReportMonth month) {
    final rows = _store.select(
      'SELECT id, payload FROM ledger_postings WHERE workspace = ? '
      'AND date BETWEEN ? AND ? ORDER BY date, id',
      [workspace.toString(), '${month.first}', '${month.last}'],
    );
    return [
      for (final row in rows)
        reportFact(
          _decodePosting(row['payload']),
          metadata(PublicId.parse(row['id']! as String)),
        ),
    ];
  }

  /// Every budget for [month] with what was spent against it. Merged
  /// categories count toward the category they were merged into.
  List<BudgetResult> budgetStatus(WorkspaceId workspace, ReportMonth month) {
    final rows = _store.select(
      'SELECT payload FROM plan_budgets WHERE workspace = ? AND month = ? '
      'ORDER BY id',
      [workspace.toString(), _month(month)],
    );
    final catalog = CategoryCatalog.restore(workspace, categories(workspace));
    final facts = [
      for (final fact in monthlyFacts(workspace, month))
        BudgetFact(workspace: workspace, report: _canonical(fact, catalog)),
    ];
    return [
      for (final row in rows)
        evaluateBudget(
          BudgetPlanCodec().decode(row['payload']! as String),
          facts,
          categories: catalog,
        ),
    ];
  }

  /// Occurrences due after [after] up to [through] that are not confirmed
  /// yet, from active templates.
  List<RecurringCandidate> dueRecurring(
    WorkspaceId workspace, {
    required BusinessDate after,
    required BusinessDate through,
  }) {
    final rows = _store.select(
      'SELECT payload FROM plan_recurring '
      'WHERE workspace = ? AND active = 1 ORDER BY id',
      [workspace.toString()],
    );
    final confirmed = {
      for (final row in _store.select(
        'SELECT template_id, due_date FROM plan_recurring_confirmed',
      ))
        '${row['template_id']}/${row['due_date']}',
    };
    return [
      for (final row in rows)
        for (final candidate in dueCandidates(
          RecurringTemplateCodec().decode(row['payload']! as String),
          after: after,
          through: through,
        ))
          if (!confirmed.contains(
            '${candidate.template.id.value}/${candidate.dueDate}',
          ))
            candidate,
    ];
  }

  PostingMetadata metadata(PublicId postingId) =>
      _readMetadata(_store.select, postingId);

  /// Category totals for `YYYY-MM`. Merged categories are reported under
  /// the category they were merged into.
  Map<(PublicId, String), MonthlyTotal> categoryTotals(
    WorkspaceId workspace,
    String month,
  ) {
    final catalog = CategoryCatalog.restore(workspace, categories(workspace));
    final rows = _store.select(
      'SELECT * FROM ledger_category_monthly WHERE workspace = ? AND month = ?',
      [workspace.toString(), month],
    );
    final totals = <(PublicId, String), MonthlyTotal>{};
    for (final row in rows) {
      final category = PublicId.parse(row['category_id'] as String);
      final key = (catalog.resolve(category).id, row['currency'] as String);
      final income = _money(row, 'income');
      final expense = _money(row, 'expense');
      final earlier = totals[key];
      totals[key] = earlier == null
          ? MonthlyTotal(income, expense)
          : MonthlyTotal(earlier.income + income, earlier.expense + expense);
    }
    return totals;
  }

  List<Map<String, Object?>> _catalog(String type, WorkspaceId workspace) {
    final rows = _store.select(
      'SELECT payload FROM catalog_entries WHERE type = ? AND workspace = ?',
      [type, workspace.toString()],
    );
    return [for (final row in rows) _json(row['payload'])];
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
final class SqlBookkeeping
    implements CardTransaction, InvestmentTransaction, PlanningTransaction {
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
  Future<bool> isLocked(PublicId postingId) async {
    final rows = _transaction.select(
      'SELECT 1 FROM card_charges WHERE posting_id = ?1 '
      'UNION ALL SELECT 1 FROM card_payments WHERE posting_id = ?1 '
      'UNION ALL SELECT 1 FROM invest_trades WHERE posting_id = ?1',
      [postingId.value],
    );
    return rows.isNotEmpty;
  }

  @override
  Future<List<Posting>> refundsOf(PublicId expenseId) async {
    final rows = _transaction.select(
      'SELECT payload FROM ledger_postings WHERE refund_of = ? '
      'ORDER BY date, id',
      [expenseId.value],
    );
    return [for (final row in rows) _decodePosting(row['payload'])];
  }

  @override
  Future<Posting?> openingOf(PublicId accountId) async {
    final rows = _transaction.select(
      "SELECT p.payload FROM ledger_postings p JOIN ledger_legs l "
      "ON l.posting_id = p.id WHERE l.account_id = ? AND p.kind = 'opening' "
      'AND NOT EXISTS (SELECT 1 FROM ledger_postings r '
      'WHERE r.reversal_of = p.id)',
      [accountId.value],
    );
    return rows.isEmpty ? null : _decodePosting(rows.single['payload']);
  }

  @override
  Future<BudgetPlan?> budget(PublicId id) async {
    final rows = _transaction.select(
      'SELECT payload FROM plan_budgets WHERE id = ?',
      [id.value],
    );
    if (rows.isEmpty) return null;
    return BudgetPlanCodec().decode(rows.single['payload']! as String);
  }

  @override
  Future<void> saveBudget(BudgetPlan plan) async {
    _transaction.execute(
      'INSERT INTO plan_budgets VALUES (?, ?, ?, ?) ON CONFLICT (id) '
      'DO UPDATE SET month = excluded.month, payload = excluded.payload',
      [
        plan.id.value,
        plan.workspace.toString(),
        _month(plan.month),
        BudgetPlanCodec().encode(plan),
      ],
    );
  }

  @override
  Future<(RecurringTemplate, bool)?> recurring(PublicId id) async {
    final rows = _transaction.select(
      'SELECT active, payload FROM plan_recurring WHERE id = ?',
      [id.value],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final template = RecurringTemplateCodec().decode(row['payload']! as String);
    return (template, row['active'] == 1);
  }

  @override
  Future<void> saveRecurring(
    RecurringTemplate template, {
    required bool active,
  }) async {
    _transaction.execute(
      'INSERT INTO plan_recurring VALUES (?, ?, ?, ?) ON CONFLICT (id) '
      'DO UPDATE SET active = excluded.active, payload = excluded.payload',
      [
        template.id.value,
        template.workspace.toString(),
        active ? 1 : 0,
        RecurringTemplateCodec().encode(template),
      ],
    );
  }

  @override
  Future<PublicId?> confirmation(
    PublicId templateId,
    BusinessDate dueDate,
  ) async {
    final rows = _transaction.select(
      'SELECT posting_id FROM plan_recurring_confirmed '
      'WHERE template_id = ? AND due_date = ?',
      [templateId.value, '$dueDate'],
    );
    if (rows.isEmpty) return null;
    return PublicId.parse(rows.single['posting_id']! as String);
  }

  @override
  Future<void> saveConfirmation(
    PublicId templateId,
    BusinessDate dueDate,
    PublicId postingId,
  ) async {
    _transaction.execute(
      'INSERT INTO plan_recurring_confirmed VALUES (?, ?, ?)',
      [templateId.value, '$dueDate', postingId.value],
    );
  }

  @override
  Future<EntryNote> noteOf(PublicId postingId) async =>
      _readNote(_transaction.select, postingId);

  @override
  Future<void> saveNote(PublicId postingId, EntryNote note) async {
    _transaction.execute(
      'INSERT INTO ledger_notes VALUES (?, ?, ?) ON CONFLICT (posting_id) '
      'DO UPDATE SET revision = excluded.revision, text = excluded.text',
      [postingId.value, note.revision, note.text],
    );
  }

  @override
  Future<Money> balance(PublicId accountId, Currency currency) async {
    final rows = _transaction.select(
      'SELECT minor_units FROM ledger_balances WHERE account_id = ?',
      [accountId.value],
    );
    return _balance(currency, rows);
  }

  @override
  Future<bool> hasUnsettledItems(PublicId accountId) async {
    final pending = _transaction.select(
      'SELECT 1 FROM card_charges '
      'WHERE card_id = ? AND posting_id IS NULL AND released = 0',
      [accountId.value],
    );
    if (pending.isNotEmpty) return true;
    final funded = _transaction.select(
      "SELECT payload FROM invest_registry WHERE type = 'account'",
    );
    for (final row in funded) {
      final account = InvestmentRecords.readAccount(_json(row['payload']));
      if (account.fundingCashAccountId != accountId) continue;
      final instruments = _transaction.select(
        'SELECT DISTINCT instrument_id FROM invest_trades WHERE account_id = ?',
        [account.id.value],
      );
      for (final instrument in instruments) {
        final id = PublicId.parse(instrument['instrument_id'] as String);
        final trades = _readTrades(_transaction.select, account.id, id);
        if (InvestmentRecords.openLots(trades).isNotEmpty) return true;
      }
    }
    return false;
  }

  @override
  Future<BrokerIdentity?> broker(PublicId id) async {
    final json = _registry('broker', id);
    return json == null ? null : InvestmentRecords.readBroker(json);
  }

  @override
  Future<void> saveBroker(BrokerIdentity broker) async =>
      _register('broker', broker.id, InvestmentRecords.broker(broker));

  @override
  Future<InvestmentAccount?> investmentAccount(PublicId id) async {
    final json = _registry('account', id);
    return json == null ? null : InvestmentRecords.readAccount(json);
  }

  @override
  Future<void> saveInvestmentAccount(InvestmentAccount account) async =>
      _register('account', account.id, InvestmentRecords.account(account));

  @override
  Future<InvestmentInstrument?> instrument(PublicId id) async {
    final json = _registry('instrument', id);
    return json == null ? null : InvestmentRecords.readInstrument(json);
  }

  @override
  Future<bool> isListed(String marketCode, String symbol) async {
    final rows = _transaction.select(
      'SELECT 1 FROM invest_listings WHERE market = ? AND symbol = ?',
      [marketCode, symbol],
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> saveInstrument(InvestmentInstrument instrument) async {
    _register(
      'instrument',
      instrument.id,
      InvestmentRecords.instrument(instrument),
    );
    _transaction.execute('INSERT INTO invest_listings VALUES (?, ?, ?)', [
      instrument.marketCode,
      instrument.symbol,
      instrument.id.value,
    ]);
  }

  @override
  Future<List<Map<String, Object?>>> trades(
    PublicId accountId,
    PublicId instrumentId,
  ) async => _readTrades(_transaction.select, accountId, instrumentId);

  @override
  Future<void> saveTrade(Map<String, Object?> trade) async {
    _transaction.execute(
      'INSERT INTO invest_trades '
      '(account_id, instrument_id, posting_id, payload) VALUES (?, ?, ?, ?)',
      [
        trade['accountId'],
        trade['instrumentId'],
        trade['postingId'],
        jsonEncode(trade),
      ],
    );
  }

  Map<String, Object?>? _registry(String type, PublicId id) {
    final rows = _transaction.select(
      'SELECT payload FROM invest_registry WHERE type = ? AND id = ?',
      [type, id.value],
    );
    return rows.isEmpty ? null : _json(rows.single['payload']);
  }

  void _register(String type, PublicId id, Map<String, Object?> json) {
    _transaction.execute('INSERT INTO invest_registry VALUES (?, ?, ?)', [
      type,
      id.value,
      jsonEncode(json),
    ]);
  }

  @override
  Future<CreditCardTerms?> cardTerms(PublicId cardId) async =>
      _readTerms(_transaction.select, cardId);

  @override
  Future<void> saveCardTerms(CreditCardTerms terms) async {
    _transaction.execute(
      'INSERT INTO card_terms VALUES (?, ?) '
      'ON CONFLICT (card_id) DO UPDATE SET payload = excluded.payload',
      [terms.cardId.value, const CreditCardTermsCodec().encode(terms)],
    );
  }

  @override
  Future<CardCharge?> cardCharge(PublicId chargeId) async {
    final rows = _transaction.select(
      'SELECT payload FROM card_charges WHERE id = ?',
      [chargeId.value],
    );
    if (rows.isEmpty) return null;
    return CardRecords.readCharge(_json(rows.single['payload']));
  }

  @override
  Future<void> saveCardCharge(CardCharge charge) async {
    _transaction.execute(
      'INSERT INTO card_charges (id, card_id, posting_id, payload) '
      'VALUES (?, ?, ?, ?) ON CONFLICT (id) '
      'DO UPDATE SET posting_id = excluded.posting_id, '
      'payload = excluded.payload',
      [
        charge.id.value,
        charge.cardId.value,
        charge.ledgerEventId?.value,
        jsonEncode(CardRecords.charge(charge)),
      ],
    );
  }

  @override
  Future<bool> isReleased(PublicId chargeId) async {
    final rows = _transaction.select(
      'SELECT 1 FROM card_charges WHERE id = ? AND released = 1',
      [chargeId.value],
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> releaseCardCharge(PublicId chargeId) async {
    _transaction.execute(
      'UPDATE card_charges SET released = 1 WHERE id = ?',
      [chargeId.value],
    );
  }

  @override
  Future<void> saveCardPayment(CardPayment payment) async {
    _transaction.execute('INSERT INTO card_payments VALUES (?, ?, ?, ?)', [
      payment.id.value,
      payment.cardId.value,
      payment.ledgerEventId.value,
      jsonEncode(CardRecords.payment(payment)),
    ]);
  }

  @override
  Future<CardInstallmentSchedule?> installmentPlan(PublicId purchase) async =>
      _readPlan(_transaction.select, purchase);

  @override
  Future<void> saveInstallmentPlan(CardInstallmentSchedule plan) async {
    _transaction.execute(
      'INSERT INTO card_installment_plans VALUES (?, ?, ?)',
      [
        plan.purchaseEventId.value,
        plan.cardId.value,
        const CardInstallmentScheduleCodec().encode(plan),
      ],
    );
  }

  @override
  Future<PostingMetadata> postingMetadata(PublicId postingId) async =>
      _readMetadata(_transaction.select, postingId);

  @override
  Future<List<Category>> categories(WorkspaceId workspace) async => [
    for (final json in _entries('category', workspace))
      CatalogCodec.readCategory(json),
  ];

  @override
  Future<List<Tag>> tags(WorkspaceId workspace) async => [
    for (final json in _entries('tag', workspace)) CatalogCodec.readTag(json),
  ];

  @override
  Future<List<Merchant>> merchants(WorkspaceId workspace) async => [
    for (final json in _entries('merchant', workspace))
      CatalogCodec.readMerchant(json),
  ];

  @override
  Future<void> saveCategory(Category category) async => _saveEntry(
    'category',
    category.id,
    category.workspace,
    CatalogCodec.category(category),
  );

  @override
  Future<void> saveTag(Tag tag) async =>
      _saveEntry('tag', tag.id, tag.workspace, CatalogCodec.tag(tag));

  @override
  Future<void> saveMerchant(Merchant merchant) async => _saveEntry(
    'merchant',
    merchant.id,
    merchant.workspace,
    CatalogCodec.merchant(merchant),
  );

  List<Map<String, Object?>> _entries(String type, WorkspaceId workspace) {
    final rows = _transaction.select(
      'SELECT payload FROM catalog_entries WHERE type = ? AND workspace = ?',
      [type, workspace.toString()],
    );
    return [for (final row in rows) _json(row['payload'])];
  }

  void _saveEntry(
    String type,
    PublicId id,
    WorkspaceId workspace,
    Map<String, Object?> json,
  ) {
    _transaction.execute(
      'INSERT INTO catalog_entries VALUES (?, ?, ?, ?) '
      'ON CONFLICT (type, id) DO UPDATE SET payload = excluded.payload',
      [type, id.value, workspace.toString(), jsonEncode(json)],
    );
  }

  @override
  Future<void> savePosting(Posting posting, PostingMetadata metadata) async {
    _transaction.execute(
      'INSERT INTO ledger_postings '
      '(id, workspace, kind, date, payload, reversal_of, refund_of) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        posting.id.value,
        posting.operation.workspace.toString(),
        posting.kind.name,
        posting.date.toString(),
        jsonEncode(PostingCodec.encode(posting)),
        posting.reversalOf?.value,
        posting.refundOf?.value,
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
    _addToCategories(posting);
    for (final tag in metadata.tags) {
      _transaction.execute('INSERT INTO ledger_posting_tags VALUES (?, ?)', [
        posting.id.value,
        tag.value,
      ]);
    }
    final merchant = metadata.merchantId;
    if (merchant != null) {
      _transaction.execute(
        'INSERT INTO ledger_posting_merchants VALUES (?, ?)',
        [posting.id.value, merchant.value],
      );
    }
  }

  /// A reversal or refund subtracts allocations in its own month.
  void _addToCategories(Posting posting) {
    final original = posting.reversedPosting ?? posting;
    // A refund takes spending back; reversing anything negates it again.
    final refund = original.kind == PostingKind.refund;
    final reversed = posting.reversedPosting != null;
    final sign = refund != reversed ? -BigInt.one : BigInt.one;
    final isIncome = original.kind == PostingKind.income;
    for (final allocation in posting.allocations) {
      final amount = allocation.amount;
      final zero = Money(amount.currency, BigInt.zero);
      final signed = Money(amount.currency, amount.minorUnits * sign);
      final key = [
        posting.operation.workspace.toString(),
        posting.date.toString().substring(0, 7),
        allocation.categoryId.value,
        amount.currency.code,
        amount.currency.scale,
      ];
      final rows = _transaction.select(
        'SELECT * FROM ledger_category_monthly WHERE workspace = ? '
        'AND month = ? AND category_id = ? AND currency = ? AND scale = ?',
        key,
      );
      var income = isIncome ? signed : zero;
      var expense = isIncome ? zero : signed;
      if (rows.isNotEmpty) {
        income += _money(rows.single, 'income');
        expense += _money(rows.single, 'expense');
      }
      _transaction.execute(
        'INSERT INTO ledger_category_monthly VALUES (?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT (workspace, month, category_id, currency, scale) '
        'DO UPDATE SET income = excluded.income, expense = excluded.expense',
        [...key, '${income.minorUnits}', '${expense.minorUnits}'],
      );
    }
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

typedef _Select = List<Map<String, Object?>> Function(
  String sql, [
  List<Object?> params,
]);

List<Map<String, Object?>> _readTrades(
  _Select select,
  PublicId accountId,
  PublicId instrumentId,
) {
  final rows = select(
    'SELECT payload FROM invest_trades '
    'WHERE account_id = ? AND instrument_id = ? ORDER BY seq',
    [accountId.value, instrumentId.value],
  );
  return [for (final row in rows) _json(row['payload'])];
}

EntryNote _readNote(_Select select, PublicId postingId) {
  final rows = select(
    'SELECT revision, text FROM ledger_notes WHERE posting_id = ?',
    [postingId.value],
  );
  if (rows.isEmpty) return const EntryNote(0, '');
  final row = rows.single;
  return EntryNote(row['revision']! as int, row['text']! as String);
}

CreditCardTerms? _readTerms(_Select select, PublicId cardId) {
  final rows = select('SELECT payload FROM card_terms WHERE card_id = ?', [
    cardId.value,
  ]);
  if (rows.isEmpty) return null;
  return const CreditCardTermsCodec().decode(rows.single['payload'] as String);
}

CardInstallmentSchedule? _readPlan(_Select select, PublicId purchase) {
  final rows = select(
    'SELECT payload FROM card_installment_plans WHERE purchase_posting_id = ?',
    [purchase.value],
  );
  if (rows.isEmpty) return null;
  final payload = rows.single['payload'] as String;
  return const CardInstallmentScheduleCodec().decode(payload);
}

PostingMetadata _readMetadata(_Select select, PublicId postingId) {
  final tags = select(
    'SELECT tag_id FROM ledger_posting_tags WHERE posting_id = ?',
    [postingId.value],
  );
  final merchant = select(
    'SELECT merchant_id FROM ledger_posting_merchants WHERE posting_id = ?',
    [postingId.value],
  );
  return PostingMetadata(
    tags: [for (final row in tags) PublicId.parse(row['tag_id'] as String)],
    merchantId: merchant.isEmpty
        ? null
        : PublicId.parse(merchant.single['merchant_id'] as String),
  );
}

String _month(ReportMonth month) =>
    '${month.year.toString().padLeft(4, '0')}-'
    '${month.month.toString().padLeft(2, '0')}';

/// The fact with every category resolved to the one it was merged into.
MonthlyFact _canonical(MonthlyFact fact, CategoryCatalog catalog) {
  if (fact.allocations.isEmpty) return fact;
  final merged = <PublicId, Money>{};
  for (final allocation in fact.allocations) {
    final id = catalog.resolve(allocation.categoryId).id;
    final earlier = merged[id];
    merged[id] = earlier == null
        ? allocation.amount
        : earlier + allocation.amount;
  }
  return MonthlyFact(
    id: fact.id,
    date: fact.date,
    kind: fact.kind,
    income: fact.income,
    expense: fact.expense,
    accountId: fact.accountId,
    merchantId: fact.merchantId,
    allocations: [
      for (final MapEntry(:key, :value) in merged.entries)
        CategoryAllocation(key, value),
    ],
    tagIds: fact.tagIds,
  );
}

Map<String, Object?> _json(Object? payload) =>
    jsonDecode(payload as String) as Map<String, Object?>;

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
