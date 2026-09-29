/// Card terms are authoritative encrypted revisions in the same generation as
/// the Ledger. Statement projections and remaining due are never stored here.
const cardRevisionColumns = [
  'workspace',
  'card_id',
  'version',
  'operation_id',
  'recorded_at',
  'state',
  'payload',
];

const cardRevisionSchema = '''CREATE TABLE card_revisions (
  workspace TEXT NOT NULL,
  card_id TEXT NOT NULL,
  version INTEGER NOT NULL CHECK(version >= 1),
  operation_id TEXT NOT NULL,
  recorded_at TEXT NOT NULL,
  state TEXT NOT NULL CHECK(state IN ('active', 'disabled')),
  payload TEXT NOT NULL,
  PRIMARY KEY (workspace, card_id, version),
  UNIQUE (workspace, operation_id),
  FOREIGN KEY (workspace, card_id) REFERENCES accounts(workspace, id)
) STRICT''';
