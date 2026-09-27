/// Categories owns its portable columns and schema fragment. The composition
/// root installs this only for explicitly staged schema 4 databases.
const categoryColumns = {
  'categories': ['workspace', 'id', 'payload'],
  'category_changes': ['workspace', 'ordinal', 'operation_id', 'id', 'payload'],
};

const categorySchema = [
  '''CREATE TABLE categories (
    workspace TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL,
    PRIMARY KEY(workspace,id)) STRICT''',
  '''CREATE TABLE category_changes (
    workspace TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>0),
    operation_id TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL,
    PRIMARY KEY(workspace,ordinal), UNIQUE(workspace,operation_id),
    FOREIGN KEY(workspace,id) REFERENCES categories(workspace,id),
    FOREIGN KEY(workspace,operation_id) REFERENCES receipts(workspace,operation_id)
      DEFERRABLE INITIALLY DEFERRED) STRICT''',
];
