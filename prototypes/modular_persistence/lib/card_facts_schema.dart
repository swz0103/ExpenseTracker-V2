/// Immutable links between card facts and committed Ledger events. Amounts are
/// smallest card-currency units; Ledger remains the balance and spend authority.
const cardPostedChargeColumns = [
  'workspace',
  'event_id',
  'card_id',
  'posted_on',
  'amount_minor',
];
const cardStatementColumns = [
  'workspace',
  'statement_id',
  'revision',
  'card_id',
  'starts_after',
  'closes_on',
  'due_on',
  'billed_minor',
  'operation_id',
];
const cardPaymentColumns = [
  'workspace',
  'event_id',
  'card_id',
  'posted_on',
  'amount_minor',
];
const cardPaymentAllocationColumns = [
  'workspace',
  'payment_event_id',
  'statement_id',
  'statement_revision',
  'card_id',
  'amount_minor',
  'operation_id',
];

const cardFactsSchema = [
  '''CREATE TABLE card_posted_charges (
    workspace TEXT NOT NULL, event_id TEXT NOT NULL, card_id TEXT NOT NULL,
    posted_on TEXT NOT NULL, amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
    PRIMARY KEY(workspace,event_id),
    FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id),
    FOREIGN KEY(workspace,card_id) REFERENCES accounts(workspace,id)
  ) STRICT''',
  '''CREATE TABLE card_statements (
    workspace TEXT NOT NULL, statement_id TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK(revision >= 1), card_id TEXT NOT NULL,
    starts_after TEXT NOT NULL, closes_on TEXT NOT NULL, due_on TEXT NOT NULL,
    billed_minor INTEGER NOT NULL CHECK(billed_minor >= 0),
    operation_id TEXT NOT NULL,
    PRIMARY KEY(workspace,statement_id,revision),
    UNIQUE(workspace,operation_id),
    UNIQUE(workspace,statement_id,revision,card_id),
    FOREIGN KEY(workspace,card_id) REFERENCES accounts(workspace,id)
  ) STRICT''',
  '''CREATE TABLE card_payments (
    workspace TEXT NOT NULL, event_id TEXT NOT NULL, card_id TEXT NOT NULL,
    posted_on TEXT NOT NULL, amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
    PRIMARY KEY(workspace,event_id),
    UNIQUE(workspace,event_id,card_id),
    FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id),
    FOREIGN KEY(workspace,card_id) REFERENCES accounts(workspace,id)
  ) STRICT''',
  '''CREATE TABLE card_payment_allocations (
    workspace TEXT NOT NULL, payment_event_id TEXT NOT NULL,
    statement_id TEXT NOT NULL, statement_revision INTEGER NOT NULL,
    card_id TEXT NOT NULL,
    amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
    operation_id TEXT NOT NULL,
    PRIMARY KEY(workspace,operation_id),
    FOREIGN KEY(workspace,payment_event_id,card_id)
      REFERENCES card_payments(workspace,event_id,card_id),
    FOREIGN KEY(workspace,statement_id,statement_revision,card_id)
      REFERENCES card_statements(workspace,statement_id,revision,card_id)
  ) STRICT''',
];
