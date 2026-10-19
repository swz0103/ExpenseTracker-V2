/// Schema migrations, oldest first. Version n is reached by applying
/// `migrations[n - 1]`. Each step and its `user_version` bump commit in one
/// transaction, so a crash can never leave a half-applied step behind.
/// Released steps are never edited; add a new step instead.
const migrations = <List<String>>[
  [
    '''
    CREATE TABLE events (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      id TEXT NOT NULL UNIQUE,
      workspace TEXT NOT NULL,
      kind TEXT NOT NULL,
      payload TEXT NOT NULL
    ) STRICT
    ''',
    'CREATE INDEX events_by_workspace ON events (workspace, seq)',
    '''
    CREATE TRIGGER events_append_only_update BEFORE UPDATE ON events
    BEGIN SELECT RAISE(ABORT, 'events are append-only'); END
    ''',
    '''
    CREATE TRIGGER events_append_only_delete BEFORE DELETE ON events
    BEGIN SELECT RAISE(ABORT, 'events are append-only'); END
    ''',
    '''
    CREATE TABLE operations (
      workspace TEXT NOT NULL,
      operation_id TEXT NOT NULL,
      input TEXT NOT NULL,
      result TEXT NOT NULL,
      PRIMARY KEY (workspace, operation_id)
    ) STRICT, WITHOUT ROWID
    ''',
    '''
    CREATE TRIGGER operations_immutable_update BEFORE UPDATE ON operations
    BEGIN SELECT RAISE(ABORT, 'operations are immutable'); END
    ''',
    '''
    CREATE TRIGGER operations_immutable_delete BEFORE DELETE ON operations
    BEGIN SELECT RAISE(ABORT, 'operations are immutable'); END
    ''',
    '''
    CREATE TABLE outbox (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      id TEXT NOT NULL UNIQUE,
      topic TEXT NOT NULL,
      payload TEXT NOT NULL
    ) STRICT
    ''',
  ],
  [
    '''
    CREATE TABLE schema_modules (
      name TEXT PRIMARY KEY,
      version INTEGER NOT NULL
    ) STRICT, WITHOUT ROWID
    ''',
  ],
  [
    // Nothing ever used the outbox; the backup schedule reads the ledger
    // directly.
    'DROP TABLE outbox',
  ],
];
