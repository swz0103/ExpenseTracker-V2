import 'dart:convert';
import 'dart:io';

import 'package:storage/storage.dart';
import 'package:test/test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

const password = 'correct horse battery';
final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);

final photo = utf8.encode('a receipt photo');

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('reset-keys-'));
  tearDown(() => directory.deleteSync(recursive: true));

  LedgerVault vaultAt(String name) =>
      LedgerVault(Directory('${directory.path}/$name'), codec: codec);

  /// What is kept in [folder], but SQLite's files of an open database.
  List<String> names(Directory folder) => [
    for (final entity in folder.listSync())
      if (!RegExp(r'-(wal|shm)$').hasMatch(entity.path))
        entity.path.split(Platform.pathSeparator).last,
  ];

  List<(String, String, String)> rowsOf(EncryptedDatabase store) => [
    for (final row in store.rows()) (row.shelf, row.id, row.body),
  ];

  /// A ledger with two records, a sealed photo and an inbox; closed.
  Future<(LedgerVault, String)> ledger(String name) async {
    final vault = vaultAt(name);
    final (open, code) = await vault.create(password);
    open.store.write((w) {
      w.put('account', 'cash', '{"name":"現金"}');
      w.put('entry', 'e1', '{"amount":120}');
    });
    final box = await FileBox.derive(open.keys, 'receipts');
    await vault.receiptsDirectory.create(recursive: true);
    File('${vault.receiptsDirectory.path}/r1.etr')
        .writeAsBytesSync(await box.seal('r1.etr', photo));
    await LedgerInbox.open(vault.directory, open.keys);
    open.close();
    return (vault, code);
  }

  Future<bool> opens(UnlockedKeyring keys, File sealed) async {
    try {
      final box = await FileBox.derive(keys, 'receipts');
      return utf8.decode(await box.open('r1.etr', sealed.readAsBytesSync())) ==
          utf8.decode(photo);
    } on Object {
      return false;
    }
  }

  test('a reset keeps the book\'s version and layout, so the book is not '
      'brought up again', () async {
    final (vault, _) = await ledger('versions');
    final open = await vault.unlockWithPassword(password);
    open.store.write(
      (w) => w.setMeta(EncryptedDatabase.bookVersionKey, 2),
      counts: false,
    );
    final before = rowsOf(open.store);
    final versionsBefore = await open.store.readApart(_versions);
    expect(versionsBefore, (book: 2, layout: EncryptedDatabase.schema));
    final reset = await open.keys.reset(password: password);
    final opened = await vault.resetKeys(open, reset.unlocked);
    addTearDown(opened.close);
    expect(rowsOf(opened.store), before);
    expect(opened.store.meta(EncryptedDatabase.bookVersionKey), 2);
    expect(await opened.store.readApart(_versions), versionsBefore);
  });

  test('a book with no version yet is given none by a reset', () async {
    final (vault, _) = await ledger('no-version');
    final open = await vault.unlockWithPassword(password);
    final reset = await open.keys.reset(password: password);
    final opened = await vault.resetKeys(open, reset.unlocked);
    addTearDown(opened.close);
    expect(opened.store.meta(EncryptedDatabase.bookVersionKey), isNull);
  });

  test('a reset re-encrypts the database and the photos (SEC-06)', () async {
    final (vault, code) = await ledger('one');
    final oldKeyring = Keyring.parse(vault.keyringFile.readAsStringSync());
    final open = await vault.unlockWithPassword(password);
    final before = rowsOf(open.store);
    final oldKeys = open.keys;
    final reset = await open.keys.reset(password: password);
    final opened = await vault.resetKeys(open, reset.unlocked);
    addTearDown(opened.close);
    expect(rowsOf(opened.store), before);
    expect(opened.keys.databaseKey, isNot(oldKeys.databaseKey));
    final r1 = File('${vault.receiptsDirectory.path}/r1.etr');
    expect(await opens(opened.keys, r1), isTrue);
    expect(await opens(oldKeys, r1), isFalse);
    expect(
      names(vault.directory),
      unorderedEquals([
        'keyring.json',
        'ledger.db',
        'receipts',
        'inbox.key',
        'inbox.pub',
      ]),
    );

    // The keyring kept before (as an older backup carries it) and the old
    // password give the old database key, which no longer opens this
    // database; nor does the old recovery code open the keyring now.
    final stale = await codec.unlockWithPassword(oldKeyring, password);
    opened.close();
    expect(
      () => EncryptedDatabase.open(
        vault.databaseFile,
        StorageKey(stale.databaseKey),
      ),
      throwsA(const StorageUnavailable(StorageProblem.wrongKey)),
    );
    await expectLater(
      vault.unlockWithRecovery(code),
      throwsA(const KeyringException(KeyringError.wrongSecret)),
    );
    final again = await vault.unlockWithRecovery(reset.recoveryCode);
    expect(rowsOf(again.store), before);
    again.close();

    // What was posted to the inbox while locked still opens.
    final posted = await vault.unlockWithPassword(password);
    addTearDown(posted.close);
    await LedgerInbox.post(vault.directory, utf8.encode('confirm'));
    final inbox = await LedgerInbox.open(vault.directory, posted.keys);
    expect((await inbox.read()).single.plain, utf8.encode('confirm'));
  });

  test('a reset that fails before its check changes nothing', () async {
    final (vault, _) = await ledger('two');
    final open = await vault.unlockWithPassword(password);
    final reset = await open.keys.reset(password: password);
    // Another ledger's keys: refused before anything is written.
    final (other, _) = await vaultAt('other').create(password);
    addTearDown(other.close);
    await expectLater(
      vault.resetKeys(open, other.keys),
      throwsA(const VaultException(VaultProblem.otherLedger)),
    );
    // The store going away part way through the copy.
    open.close();
    await expectLater(vault.resetKeys(open, reset.unlocked), throwsStateError);
    final kept = await vault.unlockWithPassword(password);
    addTearDown(kept.close);
    expect(kept.keys.databaseKey, open.keys.databaseKey);
    final r1 = File('${vault.receiptsDirectory.path}/r1.etr');
    expect(await opens(kept.keys, r1), isTrue);
    expect(
      names(vault.directory),
      unorderedEquals([
        'keyring.json',
        'ledger.db',
        'receipts',
        'inbox.key',
        'inbox.pub',
      ]),
    );
  });

  test('a crash at any step of a reset leaves one ledger with its own keys '
      'and photos', () async {
    // The files a finished reset leaves, to lay out each moment a crash
    // could stop at.
    final (done, _) = await ledger('done');
    final snapshot = Directory('${directory.path}/snapshot')..createSync();
    for (final f in done.directory.listSync(recursive: true)) {
      if (f is! File) continue;
      final path = f.path.substring(done.directory.path.length + 1);
      File('${snapshot.path}/$path')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(f.readAsBytesSync());
    }
    final open = await done.unlockWithPassword(password);
    final oldKeys = open.keys;
    final reset = await open.keys.reset(password: password);
    final newKeys = reset.unlocked;
    (await done.resetKeys(open, newKeys)).close();

    /// The old ledger as it was, with the new copy staged beside it, then
    /// [moment]'s steps taken.
    Future<LedgerVault> stoppedAt(String moment) async {
      final here = vaultAt(moment);
      final path = here.directory.path;
      for (final f in snapshot.listSync(recursive: true)) {
        if (f is! File) continue;
        final rel = f.path.substring(snapshot.path.length + 1);
        File('$path/$rel')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(f.readAsBytesSync());
      }
      done.databaseFile.copySync('$path/ledger.db.restore');
      done.keyringFile.copySync('$path/keyring.json.new');
      for (final name in ['receipts/r1.etr', 'inbox.key']) {
        File('$path/files.restore/$name')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(
            File('${done.directory.path}/$name').readAsBytesSync(),
          );
      }
      final steps = [
        'before',
        'deleted',
        'renamed',
        'set aside',
        'moved',
        'staging gone',
      ];
      final upTo = steps.indexOf(moment);
      if (upTo >= 1) File('$path/ledger.db').deleteSync();
      if (upTo >= 2) {
        File('$path/ledger.db.restore').renameSync('$path/ledger.db');
      }
      if (upTo >= 3) {
        // The first staged file (inbox.key, by name) was set aside.
        Directory('$path/files.replaced').createSync();
        File('$path/inbox.key').renameSync('$path/files.replaced/inbox.key');
      }
      if (upTo >= 4) {
        File('$path/files.restore/inbox.key').renameSync('$path/inbox.key');
        Directory('$path/files.replaced/receipts').createSync();
        File('$path/receipts/r1.etr')
            .renameSync('$path/files.replaced/receipts/r1.etr');
        File('$path/files.restore/receipts/r1.etr')
            .renameSync('$path/receipts/r1.etr');
      }
      if (upTo >= 5) {
        Directory('$path/files.restore').deleteSync(recursive: true);
      }
      return here;
    }

    for (final moment in [
      'before',
      'deleted',
      'renamed',
      'set aside',
      'moved',
      'staging gone',
    ]) {
      final here = await stoppedAt(moment);
      final back = await here.unlockWithPassword(password);
      final expected = moment == 'before' ? oldKeys : newKeys;
      expect(back.keys.databaseKey, expected.databaseKey, reason: moment);
      expect(back.store.count, 2, reason: moment);
      final r1 = File('${here.receiptsDirectory.path}/r1.etr');
      expect(await opens(back.keys, r1), isTrue, reason: moment);
      final inbox = await LedgerInbox.open(here.directory, back.keys);
      expect(await inbox.read(), isEmpty, reason: moment);
      expect(
        File('${here.directory.path}/inbox.pub').readAsStringSync(),
        File('${snapshot.path}/inbox.pub').readAsStringSync(),
        reason: '$moment: the inbox key survives',
      );
      back.close();
      expect(
        names(here.directory),
        unorderedEquals([
          'keyring.json',
          'ledger.db',
          'receipts',
          'inbox.key',
          'inbox.pub',
        ]),
        reason: moment,
      );
    }
  });

  group('restore with files', () {
    late OpenVault source;
    setUp(() async {
      final (open, _) = await vaultAt('source').create(password);
      source = open;
      source.store.write((w) => w.put('entry', 'e1', '{"amount":1}'));
    });
    tearDown(() => source.close());

    Future<void> copy(EncryptedDatabase staging) async {
      staging.write((w) {
        for (final row in source.store.rows()) {
          w.put(row.shelf, row.id, row.body);
        }
      });
    }

    test('photos go into place only with the checked copy (SEC-09)', () async {
      final (target, _) = await ledger('target');
      final r1 = File('${target.receiptsDirectory.path}/r1.etr');
      final kept = r1.readAsBytesSync();
      await expectLater(
        target.restore(source.keys, (staging) async {
          await copy(staging);
          File('${target.stagedFiles.path}/receipts/r1.etr')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('from the backup');
          throw StateError('connection lost');
        }, replacing: true),
        throwsStateError,
      );
      expect(r1.readAsBytesSync(), kept);
      expect(target.stagedFiles.existsSync(), isFalse);

      final restored = await target.restore(source.keys, (staging) async {
        await copy(staging);
        for (final name in ['r1.etr', 'r2.etr']) {
          File('${target.stagedFiles.path}/receipts/$name')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('$name from the backup');
        }
      }, replacing: true);
      restored.close();
      expect(r1.readAsStringSync(), 'r1.etr from the backup');
      expect(
        File('${target.receiptsDirectory.path}/r2.etr').readAsStringSync(),
        'r2.etr from the backup',
      );
      expect(target.stagedFiles.existsSync(), isFalse);
    });

    test('staged files left by a crash before the swap are let go', () async {
      final (target, _) = await ledger('crashed');
      final r1 = File('${target.receiptsDirectory.path}/r1.etr');
      final kept = r1.readAsBytesSync();
      // A crash while filling: the copy and its files are staged, the
      // ledger here untouched.
      File('${target.directory.path}/ledger.db.restore').writeAsStringSync('');
      File('${target.stagedFiles.path}/receipts/r1.etr')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('from the backup');
      final open = await target.unlockWithPassword(password);
      open.close();
      expect(r1.readAsBytesSync(), kept);
      expect(target.stagedFiles.existsSync(), isFalse);
    });
  });
}

/// The book's version and the file's layout, as a read apart finds them.
Future<({int? book, int layout})> _versions(StoreSnapshot s) async =>
    (book: s.book, layout: s.layout);
