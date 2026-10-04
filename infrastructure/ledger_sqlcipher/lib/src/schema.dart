part of 'ledger_store.dart';

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
  [
    // A payment entered by mistake can be voided; it then leaves the
    // statement. (A voided charge reuses card_charges.released.)
    '''
    ALTER TABLE card_payments
    ADD COLUMN voided INTEGER NOT NULL DEFAULT 0
    ''',
  ],
  [
    // Trades stay immutable; a voided one is listed here and left out of
    // every replay.
    'CREATE TABLE invest_voids (trade_id TEXT PRIMARY KEY) STRICT',
  ],
  [
    // What a foreign-currency entry was worth in the home currency when it
    // was booked (feature audit G-11).
    '''
    CREATE TABLE ledger_posting_home (
      posting_id TEXT PRIMARY KEY REFERENCES ledger_postings (id),
      value TEXT NOT NULL
    ) STRICT, WITHOUT ROWID
    ''',
  ],
]);
