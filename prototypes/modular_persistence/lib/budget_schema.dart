/// Immutable budget revisions live beside Ledger authority in the same
/// encrypted generation. A deletion appends a tombstone revision; history is
/// retained for portable backup and audit.
const budgetRevisionColumns = [
  'workspace',
  'id',
  'version',
  'operation_id',
  'recorded_at',
  'state',
  'payload',
];

const budgetRevisionSchema = '''CREATE TABLE budget_revisions (
  workspace TEXT NOT NULL,
  id TEXT NOT NULL,
  version INTEGER NOT NULL CHECK(version >= 1),
  operation_id TEXT NOT NULL,
  recorded_at TEXT NOT NULL,
  state TEXT NOT NULL CHECK(state IN ('active', 'deleted')),
  payload TEXT NOT NULL,
  PRIMARY KEY (workspace, id, version),
  UNIQUE (workspace, operation_id)
) STRICT''';
