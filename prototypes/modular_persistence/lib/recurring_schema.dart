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

const recurringOccurrenceColumns = [
  'workspace',
  'template_id',
  'due_date',
  'template_version',
  'event_id',
  'operation_id',
  'confirmed_at',
];

const recurringOccurrenceSchema = '''CREATE TABLE recurring_occurrences (
  workspace TEXT NOT NULL,
  template_id TEXT NOT NULL,
  due_date TEXT NOT NULL,
  template_version INTEGER NOT NULL CHECK(template_version >= 1),
  event_id TEXT NOT NULL,
  operation_id TEXT NOT NULL,
  confirmed_at TEXT NOT NULL,
  PRIMARY KEY (workspace, template_id, due_date),
  UNIQUE (workspace, event_id),
  UNIQUE (workspace, operation_id),
  FOREIGN KEY (workspace, template_id, template_version)
    REFERENCES recurring_revisions(workspace, id, version),
  FOREIGN KEY (workspace, event_id) REFERENCES events(workspace, id),
  FOREIGN KEY (workspace, operation_id) REFERENCES receipts(workspace, operation_id)
) STRICT''';
