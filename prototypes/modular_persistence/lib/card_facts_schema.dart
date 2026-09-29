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

const cardAuthorizationColumns = [
  'workspace',
  'charge_id',
  'card_id',
  'authorized_on',
  'currency',
  'scale',
  'amount_minor',
  'operation_id',
];
const cardAuthorizationResolutionColumns = [
  'workspace',
  'charge_id',
  'operation_id',
  'state',
  'event_id',
  'posted_on',
  'settled_minor',
  'fee_minor',
];

const cardInstallmentPlanColumns = [
  'workspace',
  'purchase_event_id',
  'card_id',
  'operation_id',
  'payload',
];

/// A plan refers to an existing posted purchase. It never creates a second
/// Ledger expense or asserts that an issuer has confirmed a statement.
const cardInstallmentPlanSchema = '''CREATE TABLE card_installment_plans (
  workspace TEXT NOT NULL, purchase_event_id TEXT NOT NULL,
  card_id TEXT NOT NULL, operation_id TEXT NOT NULL, payload TEXT NOT NULL,
  PRIMARY KEY(workspace,purchase_event_id), UNIQUE(workspace,operation_id),
  FOREIGN KEY(workspace,purchase_event_id)
    REFERENCES card_posted_charges(workspace,event_id),
  FOREIGN KEY(workspace,card_id) REFERENCES accounts(workspace,id)
) STRICT''';

/// The authorization is immutable. A single terminal fact either cancels it
/// or links it to an already committed card purchase and Ledger receipt.
const cardAuthorizationSchema = [
  '''CREATE TABLE card_authorizations (
    workspace TEXT NOT NULL, charge_id TEXT NOT NULL, card_id TEXT NOT NULL,
    authorized_on TEXT NOT NULL, currency TEXT NOT NULL,
    scale INTEGER NOT NULL CHECK(scale BETWEEN 0 AND 18),
    amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
    operation_id TEXT NOT NULL,
    PRIMARY KEY(workspace,charge_id), UNIQUE(workspace,operation_id),
    FOREIGN KEY(workspace,card_id) REFERENCES accounts(workspace,id)
  ) STRICT''',
  '''CREATE TABLE card_authorization_resolutions (
    workspace TEXT NOT NULL, charge_id TEXT NOT NULL,
    operation_id TEXT NOT NULL, state TEXT NOT NULL
      CHECK(state IN ('cancelled','posted')),
    event_id TEXT, posted_on TEXT, settled_minor INTEGER, fee_minor INTEGER,
    PRIMARY KEY(workspace,charge_id), UNIQUE(workspace,operation_id),
    UNIQUE(workspace,event_id),
    CHECK((state='cancelled' AND event_id IS NULL AND posted_on IS NULL
      AND settled_minor IS NULL AND fee_minor IS NULL) OR
      (state='posted' AND event_id IS NOT NULL AND posted_on IS NOT NULL
      AND settled_minor IS NOT NULL AND fee_minor IS NOT NULL
      AND settled_minor > 0 AND fee_minor >= 0)),
    FOREIGN KEY(workspace,charge_id)
      REFERENCES card_authorizations(workspace,charge_id),
    FOREIGN KEY(workspace,event_id)
      REFERENCES card_posted_charges(workspace,event_id)
  ) STRICT''',
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
