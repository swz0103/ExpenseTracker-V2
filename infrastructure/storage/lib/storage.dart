/// The ledger's encrypted single-file store: records kept as rows of JSON
/// on shelves, written in transactions.
library;

export 'src/encrypted_database.dart';
export 'src/no_space.dart';
export 'src/journal_store.dart'
    show JournalFill, KeptRow, PostedApart, SqlPostingStore;
