/// Tags owns its portable columns and schema fragment. The composition
/// root installs this only for explicitly staged schema 6 databases.
const tagColumns = {
  'tags': ['workspace', 'id', 'payload'],
  'tag_changes': ['workspace', 'ordinal', 'operation_id', 'id', 'payload'],
};

const tagSchema = [
  '''CREATE TABLE tags (
    workspace TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL,
    PRIMARY KEY(workspace,id)) STRICT''',
  '''CREATE TABLE tag_changes (
    workspace TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>0),
    operation_id TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL,
    PRIMARY KEY(workspace,ordinal), UNIQUE(workspace,operation_id),
    FOREIGN KEY(workspace,id) REFERENCES tags(workspace,id),
    FOREIGN KEY(workspace,operation_id) REFERENCES receipts(workspace,operation_id)
      DEFERRABLE INITIALLY DEFERRED) STRICT''',
];
