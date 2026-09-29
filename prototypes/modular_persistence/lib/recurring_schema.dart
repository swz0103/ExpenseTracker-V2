/// Immutable template revisions for a future encrypted Ledger generation.
/// This schema alone does not provide portable backup or posting receipts.
const recurringRevisionColumns = [
  'workspace',
  'id',
  'version',
  'account_id',
  'operation_id',
  'recorded_at',
  'state',
  'payload',
];

const recurringRevisionSchema = '''CREATE TABLE recurring_revisions (
  workspace TEXT NOT NULL,
  id TEXT NOT NULL,
  version INTEGER NOT NULL CHECK(version >= 1),
  account_id TEXT NOT NULL,
  operation_id TEXT NOT NULL,
  recorded_at TEXT NOT NULL,
  state TEXT NOT NULL CHECK(state IN ('active', 'deleted')),
  payload TEXT NOT NULL,
  PRIMARY KEY (workspace, id, version),
  UNIQUE (workspace, operation_id),
  FOREIGN KEY (workspace, account_id) REFERENCES accounts(workspace, id)
) STRICT''';
