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

    Future<void> copy(RowStore staging) async {
      staging.write((w) {
        for (final row in source.store.rows()) {
          w.put(row.shelf, row.id, row.body);
        }
      });
    }

    List<(String, String, String)> rowsOf(RowStore store) => [
      for (final row in store.rows()) (row.shelf, row.id, row.body),
    ];

    test('a checked copy becomes the ledger', () async {
      final restored = await target.restore(source.keys, copy);
      expect(rowsOf(restored.store), rowsOf(source.store));
      restored.close();
      expect(target.exists, isTrue);
      final files = target.directory.listSync();
      final names = files.map((file) => file.uri.pathSegments.last);
      expect(names, unorderedEquals(['keyring.json', 'ledger.db']));
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

    test('a ledger is replaced only when asked, and kept on a failure', () async {
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
    });

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
