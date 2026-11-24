/// The ledger's encrypted single-file store: records kept as rows of JSON
/// on shelves, written in transactions.
library;

export 'src/encrypted_database.dart';
export 'src/no_space.dart';

// What a read or write of the file throws, as SQLite says it: told apart
// by [isNoSpace] and [EncryptedDatabase.damageIn].
export 'package:sqlite3/sqlite3.dart' show SqliteException;

export 'src/journal_store.dart'
    show JournalFill, KeptRow, PostedApart, SqlPostingStore;
