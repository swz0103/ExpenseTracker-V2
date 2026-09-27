/// Merchants owns its portable columns and schema fragment. The composition
/// root installs this only for explicitly staged schema 7 databases.
const merchantColumns = {
  'merchants': ['workspace', 'id', 'payload'],
  'merchant_changes': ['workspace', 'ordinal', 'operation_id', 'id', 'payload'],
};

const merchantSchema = [
  '''CREATE TABLE merchants (
    workspace TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL,
    PRIMARY KEY(workspace,id)) STRICT''',
  '''CREATE TABLE merchant_changes (
    workspace TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>0),
    operation_id TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL,
    PRIMARY KEY(workspace,ordinal), UNIQUE(workspace,operation_id),
    FOREIGN KEY(workspace,id) REFERENCES merchants(workspace,id),
    FOREIGN KEY(workspace,operation_id) REFERENCES receipts(workspace,operation_id)
      DEFERRABLE INITIALLY DEFERRED) STRICT''',
];
