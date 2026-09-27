/// Ledger owns attribution rows; Categories owns identity and revision history.
const allocationReferenceColumns = [
  'workspace',
  'event_id',
  'category_id',
  'amount',
  'category_version',
  'category_sequence',
];

const allocationReferenceSchema = '''CREATE TABLE allocations (
  workspace TEXT NOT NULL, event_id TEXT NOT NULL, category_id TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK(amount>0),
  category_version INTEGER NOT NULL CHECK(category_version>0),
  category_sequence INTEGER NOT NULL CHECK(category_sequence>0),
  PRIMARY KEY(workspace,event_id,category_id),
  FOREIGN KEY(workspace,event_id) REFERENCES events(workspace,id),
  FOREIGN KEY(workspace,category_id) REFERENCES categories(workspace,id)
    DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY(workspace,category_sequence) REFERENCES category_changes(workspace,ordinal)
    DEFERRABLE INITIALLY DEFERRED) STRICT''';
