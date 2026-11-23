import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/persistence/book_migrations.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/upgrade_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';

/// D26: a backup (version 5) carries the book's version, so a book
/// restored from one taken by this version opens as it was kept: no
/// upgrade step runs and no copy is kept before an upgrade that would do
/// nothing. An older backup carries none: the book is brought up
/// as before (the fixtures of old_books_test.dart restore through it).
void main() {
  final clock = FixedClock(UtcInstant(DateTime.utc(2026, 11, 23, 4)));
  final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);
  late Directory directory;
  var n = 0;

  setUp(() => directory = Directory.systemTemp.createTempSync('book-v-'));
  tearDown(() => directory.deleteSync(recursive: true));

  EncryptedDatabase open() => EncryptedDatabase.open(
    File('${directory.path}/store-${n++}.db'),
    StorageKey.random(),
  );

  test('a book restored from this version\'s backup is not brought up '
      'again, and no copy is kept first', () async {
    final keys = (await codec.create('correct horse battery')).unlocked;
    final source = open();
    addTearDown(source.close);
    // A new book: given its first records and marked at this version.
    await SqlLedgerDataSource(source, clock: clock).load();
    expect(source.meta(EncryptedDatabase.bookVersionKey), bookVersion);
    final file = File('${directory.path}/backup.etbk');
    final header = await LedgerBackup.write(
      store: source,
      keys: keys,
      file: file,
      backupId: 'b',
      createdAt: DateTime.utc(2026, 11, 23, 4),
    );
    expect(header.version, 5);
    expect(header.book, bookVersion);

    final into = open();
    addTearDown(into.close);
    await LedgerBackup.restore(
      file: file,
      keys: keys,
      into: into,
      accept: SqlLedgerDataSource.check,
    );
    expect(into.meta(EncryptedDatabase.bookVersionKey), bookVersion);
    final revision = into.revision;
    var copies = 0;
    final restored = SqlLedgerDataSource(
      into,
      clock: clock,
      beforeUpgrade: () async {
        copies++;
        return const UpgradeBackupKept();
      },
    );
    expect(await restored.bringUp(), isNull);
    final ledger = await restored.load();
    expect(copies, 0);
    // Nothing was written as it opened.
    expect(into.revision, revision);
    expect(ledger.accounts.all.map((a) => a.name), ['現金', '銀行帳戶']);
  });

  test('an older backup (here version 3) still restores, and its book is '
      'brought up, a copy kept first', () async {
    // The backup 0.22.0 kept (old_books_test.dart has its records).
    final file = File('test/fixtures/books/0.22.0/backup.etbk');
    final header = await LedgerBackup.readHeader(file);
    expect(header.version, 3);
    expect(header.book, isNull);
    final keys = await KeyringCodec(minimumPassword: 6)
        .unlockWithPassword(header.keyring, 'fixture password');
    final into = open();
    addTearDown(into.close);
    await LedgerBackup.restore(
      file: file,
      keys: keys,
      into: into,
      accept: SqlLedgerDataSource.check,
      onFile: (_, _) async {},
    );
    expect(into.meta(EncryptedDatabase.bookVersionKey), isNull);
    var copies = 0;
    final restored = SqlLedgerDataSource(
      into,
      clock: clock,
      beforeUpgrade: () async {
        copies++;
        return const UpgradeBackupKept();
      },
    );
    await restored.load();
    expect(copies, 1);
    expect(into.meta(EncryptedDatabase.bookVersionKey), bookVersion);
  });
}
