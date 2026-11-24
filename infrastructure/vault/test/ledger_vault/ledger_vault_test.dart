import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:storage/storage.dart';
import 'package:test/test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

const password = 'correct horse battery';
final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);

Matcher fails(VaultProblem problem) =>
    throwsA(isA<VaultException>().having((e) => e.problem, 'problem', problem));

const wrongSecret = KeyringException(KeyringError.wrongSecret);

/// Stands in for an Android Keystore key.
final class FakeDeviceKey implements DeviceKeyWrapper {
  final _secrets = <String, List<int>>{};

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) async {
    final handle = 'blob-${_secrets.length}:${context.join(',')}';
    _secrets[handle] = List.of(secret);
    return handle.codeUnits;
  }

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) async {
    final handle = String.fromCharCodes(wrapped);
    final secret = _secrets[handle];
    if (secret == null || !handle.endsWith(':${context.join(',')}')) {
      throw StateError('not this device');
    }
    return secret;
  }
}

void main() {
  late Directory directory;
  late LedgerVault vault;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('ledger-vault-');
    vault = LedgerVault(Directory('${directory.path}/ledger'), codec: codec);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  void keepOne(OpenVault open) =>
      open.store.write((w) => w.put('account', 'cash', '{"name":"現金"}'));

  test('a closed ledger reopens with the keys it was open with', () async {
    final (open, _) = await vault.create(password);
    keepOne(open);
    final keys = open.keys;
    open.close();
    final again = await vault.reopen(keys);
    addTearDown(again.close);
    expect(again.store.rows().single.id, 'cash');
    expect(again.keys, same(keys));
  });

  test('keys of another ledger do not reopen this one', () async {
    final (open, _) = await vault.create(password);
    open.close();
    final other = LedgerVault(
      Directory('${directory.path}/other'),
      codec: codec,
    );
    final (theirs, _) = await other.create(password);
    theirs.close();
    await expectLater(
      vault.reopen(theirs.keys),
      fails(VaultProblem.otherLedger),
    );
  });

  test('a new ledger reopens with the password or recovery code', () async {
    expect(vault.exists, isFalse);
    await expectLater(
      vault.unlockWithPassword(password),
      fails(VaultProblem.missing),
    );
    final (open, recovery) = await vault.create(password);
    keepOne(open);
    open.close();
    expect(vault.exists, isTrue);
    expect(vault.keyringFile.readAsStringSync(), isNot(contains(recovery)));
    await expectLater(
      vault.create(password),
      fails(VaultProblem.alreadyExists),
    );

    final again = await vault.unlockWithPassword(password);
    expect(again.store.count, 1);
    again.close();
    final recovered = await vault.unlockWithRecovery(recovery);
    expect(recovered.store.count, 1);
    recovered.close();
    await expectLater(
      vault.unlockWithPassword('wrong password here'),
      throwsA(wrongSecret),
    );
  });

  test(
    'a ledger whose database is gone is refused, not opened empty',
    () async {
      final (open, recovery) = await vault.create(password);
      keepOne(open);
      open.close();
      vault.databaseFile.deleteSync();
      // Opening would start an empty book as if nothing had been kept.
      await expectLater(
        vault.unlockWithPassword(password),
        fails(VaultProblem.missingDatabase),
      );
      await expectLater(
        vault.unlockWithRecovery(recovery),
        fails(VaultProblem.missingDatabase),
      );
      expect(vault.databaseFile.existsSync(), isFalse, reason: 'none made');
      expect(vault.keyringFile.existsSync(), isTrue, reason: 'keys kept');
    },
  );

  group('a damaged database (D94)', () {
    const damaged = StorageUnavailable(StorageProblem.damaged);

    setUp(() {
      vault = LedgerVault(
        Directory('${directory.path}/ledger'),
        codec: codec,
        now: () => DateTime.utc(2026, 11, 24, 9, 58, 50),
      );
    });

    Future<String> made() async {
      final (open, recovery) = await vault.create(password);
      keepOne(open);
      open.close();
      return recovery;
    }

    test('of no bytes is set aside, told, never opened empty', () async {
      await made();
      vault.databaseFile.writeAsBytesSync(const []);
      await expectLater(vault.unlockWithPassword(password), throwsA(damaged));
      expect(vault.databaseFile.existsSync(), isFalse);
      final aside = vault.damagedCopies().single;
      expect(
        aside.uri.pathSegments.last,
        'ledger-damaged-2026-11-24T09-58-50.000Z.db',
      );
      expect(aside.lengthSync(), 0, reason: 'kept as it was');
      // Asked again, it is still damaged: no empty book in its place.
      await expectLater(vault.unlockWithPassword(password), throwsA(damaged));
      expect(vault.databaseFile.existsSync(), isFalse);
      expect(vault.keyringFile.existsSync(), isTrue, reason: 'keys kept');
    });

    test('a first page damaged is damage, not a wrong key', () async {
      final recovery = await made();
      final bytes = vault.databaseFile.readAsBytesSync();
      bytes[100] ^= 0x01;
      vault.databaseFile.writeAsBytesSync(bytes);
      await expectLater(vault.unlockWithRecovery(recovery), throwsA(damaged));
      expect(vault.damagedCopies().single.readAsBytesSync(), bytes);
    });

    test('a wrong password is still a wrong password', () async {
      await made();
      await expectLater(
        vault.unlockWithPassword('wrong password here'),
        throwsA(wrongSecret),
      );
      expect(vault.damagedCopies(), isEmpty);
    });

    test('a restore puts a backup where the damaged one was', () async {
      await made();
      vault.databaseFile.writeAsBytesSync(const []);
      await expectLater(vault.unlockWithPassword(password), throwsA(damaged));
      final keys = await codec.unlockWithPassword(
        Keyring.parse(vault.keyringFile.readAsStringSync()),
        password,
      );
      final restored = await vault.restore(
        keys,
        (staging) async =>
            staging.write((w) => w.put('account', 'bank', '{"name":"銀行"}')),
        replacing: true,
      );
      addTearDown(restored.close);
      expect(restored.store.rows().single.id, 'bank');
      // The damaged one is still kept aside.
      expect(vault.damagedCopies(), hasLength(1));
    });

    Future<UnlockedKeyring> keysNow() => codec.unlockWithPassword(
      Keyring.parse(vault.keyringFile.readAsStringSync()),
      password,
    );

    /// Spoils the page a table [named] starts on, as a bad sector would.
    Future<void> spoil(String named) async {
      final keys = await keysNow();
      final raw = sqlite3.open(vault.databaseFile.path)
        ..execute('PRAGMA key = "x\'${StorageKey(keys.databaseKey).hex}\'"');
      final root =
          raw.select('SELECT rootpage FROM sqlite_master WHERE name = ?', [
                named,
              ]).single['rootpage']
              as int;
      raw.close();
      final bytes = vault.databaseFile.readAsBytesSync();
      // Bytes inside the page, past its header: 4096 x (page - 1) + 200.
      for (var i = 0; i < 64; i++) {
        bytes[EncryptedDatabase.pageSize * (root - 1) + 200 + i] ^= 0x5a;
      }
      vault.databaseFile.writeAsBytesSync(bytes);
    }

    /// A ledger with records and a posting of its journal beside them.
    Future<void> withJournal() async {
      final (open, _) = await vault.create(password);
      keepOne(open);
      open.close();
      final keys = await keysNow();
      sqlite3.open(vault.databaseFile.path)
        ..execute('PRAGMA key = "x\'${StorageKey(keys.databaseKey).hex}\'"')
        ..execute(
          "INSERT INTO posting VALUES (1, 0, 1, 'TWD', 5, 0, 0, '', "
          '20260101, 1)',
        )
        ..close();
    }

    test('two set aside at the same moment are both kept, in order', () async {
      await made();
      final first = await vault.setAsideDamaged();
      // Another file in its place, set aside at the same moment.
      vault.databaseFile.writeAsBytesSync(const [1]);
      final second = await vault.setAsideDamaged();
      expect(
        first!.uri.pathSegments.last,
        'ledger-damaged-2026-11-24T09-58-50.000Z.db',
      );
      expect(
        second!.uri.pathSegments.last,
        'ledger-damaged-2026-11-24T09-58-50.000Z~002.db',
      );
      expect(vault.damagedCopies(), [
        isA<File>().having((f) => f.path, 'path', first.path),
        isA<File>().having((f) => f.path, 'path', second.path),
      ]);
    });

    test('a restore keeps the newest two copies set aside, no more', () async {
      expect(LedgerVault.keptDamagedCopies, 2);
      await made();
      for (var i = 0; i < 3; i++) {
        vault.databaseFile.writeAsBytesSync(const []);
        await expectLater(vault.unlockWithPassword(password), throwsA(damaged));
        (await vault.restore(
          await keysNow(),
          (staging) async => staging.write((w) => w.put('a', 'b', '{}')),
          replacing: true,
        )).close();
      }
      // Three set aside; the oldest let go at the third restore.
      expect(
        [for (final f in vault.damagedCopies()) f.uri.pathSegments.last],
        [
          'ledger-damaged-2026-11-24T09-58-50.000Z~002.db',
          'ledger-damaged-2026-11-24T09-58-50.000Z~003.db',
        ],
      );
    });

    test(
      'a first launch cut short before any record opens as a new book',
      () async {
        final (open, _) = await vault.create(password);
        open.close();
        // As a phone stopped mid-setup leaves it: no bytes, nothing kept.
        vault.databaseFile.writeAsBytesSync(const []);
        final opened = await vault.unlockWithPassword(password);
        addTearDown(opened.close);
        expect(opened.store.count, 0);
        expect(vault.damagedCopies(), isEmpty);
      },
    );

    test('a journal found damaged is made again from the records, which '
        'are all kept (D102)', () async {
      await withJournal();
      await spoil('posting');
      final spoiled = vault.databaseFile.readAsBytesSync();
      await vault.noteJournalDamaged();
      final opened = await vault.unlockWithPassword(password);
      addTearDown(opened.close);
      expect(opened.store.rows().single.id, 'cash');
      expect(opened.store.journal.postingCount, 0, reason: 'posted afresh');
      expect(opened.store.integrityCheck(), 'ok');
      // The old file kept as it was, to send for a look (review 18).
      expect(vault.damagedCopies().single.readAsBytesSync(), spoiled);
    });

    test('books made again keep the newest two old files once the last '
        'has opened (review 18)', () async {
      await withJournal();
      for (var i = 0; i < 3; i++) {
        expect(await vault.salvage(await keysNow()), isTrue);
      }
      // Not one let go before the book made again has opened.
      expect(vault.damagedCopies(), hasLength(3));
      final opened = await vault.unlockWithPassword(password);
      addTearDown(opened.close);
      expect(opened.store.rows().single.id, 'cash');
      expect(
        [for (final f in vault.damagedCopies()) f.uri.pathSegments.last],
        [
          'ledger-damaged-2026-11-24T09-58-50.000Z~002.db',
          'ledger-damaged-2026-11-24T09-58-50.000Z~003.db',
        ],
      );
    });

    test('records that cannot be read are not made again: damage', () async {
      await withJournal();
      await spoil('rows');
      final before = vault.databaseFile.readAsBytesSync();
      expect(await vault.salvage(await keysNow()), isFalse);
      expect(vault.databaseFile.readAsBytesSync(), before);
    });

    test('nothing to set aside when there is no database', () async {
      expect(await vault.setAsideDamaged(), isNull);
      expect(vault.damagedCopies(), isEmpty);
    });
  });

  test('a changed password is saved; another ledger is refused', () async {
    final (open, _) = await vault.create(password);
    open.close();
    final changed = await open.keys.changePassword('a brand new password');
    await vault.save(changed);
    await expectLater(vault.unlockWithPassword(password), throwsA(wrongSecret));
    (await vault.unlockWithPassword('a brand new password')).close();

    final stranger = await codec.create(password);
    await expectLater(
      vault.save(stranger.unlocked),
      fails(VaultProblem.otherLedger),
    );
  });

  test('a device key opens the ledger without the password', () async {
    final device = FakeDeviceKey();
    final (open, _) = await vault.create(password);
    keepOne(open);
    await open.updateKeys(await open.keys.addDevice('phone-1', device));
    expect(open.keys.keyring.deviceIds, ['phone-1']);
    open.close();

    final unlocked = await vault.unlockWithDevice('phone-1', device);
    expect(unlocked.store.count, 1);
    unlocked.close();
    await expectLater(
      vault.unlockWithDevice('phone-1', FakeDeviceKey()),
      throwsA(wrongSecret),
    );
  });

  test('a crash while replacing the keyring keeps a usable one', () async {
    final (open, _) = await vault.create(password);
    open.close();
    vault.keyringFile.renameSync('${vault.keyringFile.path}.new');
    expect(vault.exists, isTrue);
    (await vault.unlockWithPassword(password)).close();
    expect(vault.keyringFile.existsSync(), isTrue);

    // A crash while writing the very first keyring leaves half a file:
    // that is no ledger, so setup can run again.
    final fresh = LedgerVault(
      Directory('${directory.path}/fresh'),
      codec: codec,
    );
    fresh.directory.createSync();
    File('${fresh.directory.path}/keyring.json.new').writeAsStringSync('{"id');
    expect(fresh.exists, isFalse);
    await expectLater(
      fresh.unlockWithPassword(password),
      fails(VaultProblem.missing),
    );
    final (again, _) = await fresh.create(password);
    again.close();
    expect(fresh.exists, isTrue);

    vault.keyringFile.writeAsStringSync('{"broken": true}');
    await expectLater(
      vault.unlockWithPassword(password),
      fails(VaultProblem.damagedKeyring),
    );
  });

  test('a restored keyring opens a fresh database with its key', () async {
    final source = LedgerVault(
      Directory('${directory.path}/source'),
      codec: codec,
    );
    final (open, _) = await source.create(password);
    open.close();
    final header = await codec.unlockWithPassword(open.keys.keyring, password);

    final adopted = await vault.adopt(header);
    expect(adopted.store.count, 0);
    expect(adopted.keys.databaseKey, open.keys.databaseKey);
    adopted.close();
    await expectLater(vault.adopt(header), fails(VaultProblem.alreadyExists));
  });

  test('a ledger adopted leaves no note of a journal found damaged before '
      'it (review 18)', () async {
    final source = LedgerVault(
      Directory('${directory.path}/source'),
      codec: codec,
    );
    final (open, _) = await source.create(password);
    open.close();
    await vault.noteJournalDamaged();
    final marker = File('${vault.directory.path}/journal.damaged');
    expect(marker.existsSync(), isTrue);
    (await vault.adopt(open.keys)).close();
    expect(marker.existsSync(), isFalse);
  });

  test('a write is kept when its note cannot be written; the failure is '
      'told (review 18)', () async {
    final failed = <Object>[];
    final noting = LedgerVault(
      Directory('${directory.path}/noting'),
      codec: codec,
      noteFailed: (error, _) => failed.add(error),
    );
    final (open, _) = await noting.create(password);
    addTearDown(open.close);
    // A folder where the note goes: it cannot be written.
    Directory('${noting.directory.path}/ledger.db.kept').createSync();
    keepOne(open);
    expect(open.store.rows().single.id, 'cash');
    expect(failed, [isA<FileSystemException>()]);
  });

  test('a ledger of the old format is set aside for a new one', () async {
    final (open, _) = await vault.create(password);
    keepOne(open);
    open.close();
    // What an earlier build left: the event-journal tables.
    final key = StorageKey(open.keys.databaseKey).hex;
    sqlite3.open(vault.databaseFile.path)
      ..execute('PRAGMA key = "x\'$key\'"')
      ..execute('CREATE TABLE events (seq INTEGER PRIMARY KEY)')
      ..close();

    final again = await vault.unlockWithPassword(password);
    addTearDown(again.close);
    expect(again.store.count, 0);
    expect(File('${vault.directory.path}/ledger-v2.db').existsSync(), isTrue);
  });

  group('restore', () {
    late OpenVault source;
    late LedgerVault target;

    setUp(() async {
      final from = LedgerVault(
        Directory('${directory.path}/source'),
        codec: codec,
      );
      final created = await from.create(password);
      source = created.$1;
      keepOne(source);
      target = LedgerVault(Directory('${directory.path}/target'), codec: codec);
    });

    tearDown(() => source.close());

    Future<void> copy(EncryptedDatabase staging) async {
      staging.write((w) {
        for (final row in source.store.rows()) {
          w.put(row.shelf, row.id, row.body);
        }
      });
    }

    List<(String, String, String)> rowsOf(EncryptedDatabase store) => [
      for (final row in store.rows()) (row.shelf, row.id, row.body),
    ];

    test(
      'a crash at any step of replacing a ledger leaves one that opens',
      () async {
        // The restored files as a finished restore leaves them, to lay out
        // each moment a crash could stop at.
        final done = LedgerVault(
          Directory('${directory.path}/done'),
          codec: codec,
        );
        (await done.restore(source.keys, copy)).close();
        const old = 'another password';

        Future<LedgerVault> stoppedAt(String moment) async {
          final here = LedgerVault(
            Directory('${directory.path}/$moment'),
            codec: codec,
          );
          final (open, _) = await here.create(old);
          open.store.write((w) => w.put('account', 'old', '{"name":"舊"}'));
          open.close();
          final path = here.directory.path;
          done.databaseFile.copySync('$path/ledger.db.restore');
          done.keyringFile.copySync('$path/keyring.json.new');
          if (moment != 'before') File('$path/ledger.db').deleteSync();
          if (moment == 'renamed') {
            File('$path/ledger.db.restore').renameSync('$path/ledger.db');
          }
          return here;
        }

        // The new keyring written, nothing replaced yet: the old ledger.
        final before = await stoppedAt('before');
        final kept = await before.unlockWithPassword(old);
        expect(rowsOf(kept.store), [('account', 'old', '{"name":"舊"}')]);
        kept.close();
        expect(
          before.directory.listSync().map((f) => f.uri.pathSegments.last),
          unorderedEquals(['keyring.json', 'ledger.db', 'ledger.db.kept']),
        );

        // The old database gone, or the copy in its place: the new ledger.
        for (final moment in ['deleted', 'renamed']) {
          final here = await stoppedAt(moment);
          expect(here.exists, isTrue, reason: moment);
          final back = await here.unlockWithPassword(password);
          expect(rowsOf(back.store), rowsOf(source.store), reason: moment);
          back.close();
        }
      },
    );

    test('a checked copy becomes the ledger', () async {
      final restored = await target.restore(source.keys, copy);
      expect(rowsOf(restored.store), rowsOf(source.store));
      restored.close();
      expect(target.exists, isTrue);
      final files = target.directory.listSync();
      final names = files.map((file) => file.uri.pathSegments.last);
      expect(
        names,
        unorderedEquals(['keyring.json', 'ledger.db', 'ledger.db.kept']),
      );
    });

    test('a failure part way leaves no ledger and can be retried', () async {
      await expectLater(
        target.restore(source.keys, (staging) async {
          await copy(staging);
          throw StateError('connection lost');
        }),
        throwsStateError,
      );
      expect(target.exists, isFalse);
      expect(target.directory.listSync(), isEmpty);

      final restored = await target.restore(source.keys, copy);
      restored.close();
      final reopened = await target.unlockWithPassword(password);
      addTearDown(reopened.close);
      expect(rowsOf(reopened.store), rowsOf(source.store));
    });

    test(
      'a ledger is replaced only when asked, and kept on a failure',
      () async {
        final (open, _) = await target.create('another password');
        open.store.write((w) => w.put('account', 'old', '{"name":"舊"}'));
        open.close();
        await expectLater(
          target.restore(source.keys, (staging) async {
            await copy(staging);
            throw StateError('connection lost');
          }, replacing: true),
          throwsStateError,
        );
        final kept = await target.unlockWithPassword('another password');
        expect(rowsOf(kept.store).single.$2, 'old');
        kept.close();

        final restored = await target.restore(
          source.keys,
          copy,
          replacing: true,
        );
        restored.close();
        final reopened = await target.unlockWithPassword(password);
        addTearDown(reopened.close);
        expect(rowsOf(reopened.store), rowsOf(source.store));
      },
    );

    test('an existing ledger is never replaced', () async {
      final (open, _) = await target.create(password);
      open.close();
      await expectLater(
        target.restore(source.keys, copy),
        fails(VaultProblem.alreadyExists),
      );
    });
  });
}
