import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/core/messages/key_failures.dart'
    show describeUnlockFailure;
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

const password = 'correct horse battery';

/// The host's stand-in for the phone's Keystore: what it wraps is kept in
/// memory and opens only for its context, as the real key does; the blob
/// on disk is a handle, never the secret.
final class FakeKeystore implements DeviceKeyWrapper {
  final _kept = <String, (List<int>, List<int>)>{};

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) async {
    final handle = 'sealed-${_kept.length}';
    _kept[handle] = (List.of(secret), List.of(context));
    return utf8.encode(handle);
  }

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) async {
    final entry = _kept[utf8.decode(wrapped)];
    if (entry == null || !listEquals(entry.$2, context)) {
      throw StateError('not sealed here');
    }
    return entry.$1;
  }
}

/// The keys of a ledger at start: the sealed key without a password, the
/// recovery code, restoring and resetting (SEC-01, SEC-04, SEC-06, SEC-09,
/// F91); run by startup_test.dart.
void startupKeyTests() {
  late Directory directory;
  late LedgerVault vault;
  late FakeKeystore keystore;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('startup-keys-');
    vault = LedgerVault(
      directory,
      codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
    );
    keystore = FakeKeystore();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  Startup startup() => Startup(vault, quickKey: keystore);

  /// Every byte kept in [directory], to look for a secret in plain form.
  String everything() => [
    for (final f in directory.listSync(recursive: true))
      if (f is File) latin1.decode(f.readAsBytesSync()),
  ].join('\n');

  group('a ledger without a password (SEC-01)', () {
    test('keeps its key sealed, never in plain form', () async {
      final first = startup();
      await first.setUpWithoutPassword();
      final secret = await first.quickSecret();
      first.lock();
      expect(File('${directory.path}/quick-open.key').existsSync(), isFalse);
      expect(File('${directory.path}/quick-open.sealed').existsSync(), isTrue);
      expect(everything(), isNot(contains(secret)));

      final again = startup();
      expect(again.passwordless, isTrue);
      await again.openQuietly();
      expect(again.state, isA<Ready>());
      again.lock();

      // Without the phone's key the sealed file opens nothing.
      final elsewhere = Startup(vault, quickKey: FakeKeystore());
      await expectLater(elsewhere.openQuietly(), throwsStateError);
    });

    test('a key kept in plain form by an earlier version is sealed at the '
        'first open, and the plain file overwritten and removed', () async {
      // As 0.22 left it: the ledger's password, in plain form beside it.
      const secret = 'eW91IHdvdWxkIG5vdCBndWVzcyB0aGlzIG9uZSBlaXRoZXI=';
      final (open, _) = await vault.create(secret);
      open.close();
      File('${directory.path}/recovery-given').writeAsStringSync('');
      final plain = File('${directory.path}/quick-open.key')
        ..writeAsStringSync(secret);

      final first = startup();
      expect(first.state, isA<Locked>());
      expect(first.passwordless, isTrue);
      await first.openQuietly();
      expect(first.state, isA<Ready>());
      first.lock();
      expect(plain.existsSync(), isFalse);
      expect(File('${directory.path}/quick-open.sealed').existsSync(), isTrue);
      expect(everything(), isNot(contains(secret)));

      // From then on it opens from the sealed key alone.
      final again = startup();
      expect(again.passwordless, isTrue);
      await again.openQuietly();
      expect(again.state, isA<Ready>());
      again.lock();
    });
  });

  group('the recovery code (SEC-04)', () {
    test('opens the ledger without dropping the password, and asks for a '
        'new one', () async {
      final first = startup();
      final code = await first.setUp(password);
      first.lock();

      final recovered = startup();
      await recovered.unlockWithRecovery(code);
      expect(recovered.state, isA<Ready>());
      expect(recovered.needsNewPassword, isTrue);
      expect(recovered.passwordless, isFalse);
      expect(File('${directory.path}/quick-open.key').existsSync(), isFalse);
      expect(File('${directory.path}/quick-open.sealed').existsSync(), isFalse);
      // Not set yet: the old password still opens it.
      recovered.lock();
      final old = startup();
      await old.unlockWithPassword(password);
      expect(old.needsNewPassword, isFalse);
      old.lock();

      final again = startup();
      await again.unlockWithRecovery(code);
      await expectLater(
        again.setNewPassword('123456'),
        throwsA(const KeyringException(KeyringError.weakPassword)),
      );
      expect(again.needsNewPassword, isTrue);
      await again.setNewPassword('a brand new password');
      expect(again.needsNewPassword, isFalse);
      expect(again.passwordless, isFalse);
      again.lock();

      final after = startup();
      await expectLater(
        after.unlockWithPassword(password),
        throwsA(const KeyringException(KeyringError.wrongSecret)),
      );
      await after.unlockWithPassword('a brand new password');
      expect(after.state, isA<Ready>());
      after.lock();
    });

    test('opening without a password is only by an explicit choice', () async {
      final first = startup();
      final code = await first.setUp(password);
      first.lock();
      final recovered = startup();
      await recovered.unlockWithRecovery(code);
      await recovered.openWithoutPassword();
      expect(recovered.needsNewPassword, isFalse);
      expect(recovered.passwordless, isTrue);
      expect(File('${directory.path}/quick-open.key').existsSync(), isFalse);
      recovered.lock();
      final quiet = startup();
      await quiet.openQuietly();
      expect(quiet.state, isA<Ready>());
      quiet.lock();
    });

    test(
      'a backup passphrase opens the ledger where the code is asked',
      () async {
        final first = startup();
        await first.setUp(password);
        final open = (first.state as Ready).vault;
        await open.updateKeys(
          await open.keys.setPassphrase('a passphrase for backups'),
        );
        first.lock();
        final locked = startup();
        expect((locked.state as Locked).passphrase, isTrue);
        await locked.unlockWithRecovery('a passphrase for backups');
        expect(locked.needsNewPassword, isTrue);
        locked.lock();
      },
    );
  });

  group('restoring a backup', () {
    late Directory source;
    late File backup;
    late String code;

    setUp(() async {
      source = Directory.systemTemp.createTempSync('startup-keys-source-');
      backup = File('${source.path}/backup.etbk');
      final from = Startup(
        LedgerVault(
          source,
          codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
        ),
        quickKey: keystore,
      );
      code = await from.setUp('the other password');
      final open = (from.state as Ready).vault;
      open.store.write((w) => w.put('entry', 'e1', '{"amount":1}'));
      final photo = File('${source.path}/r1.etr')..writeAsStringSync('photo');
      await LedgerBackup.write(
        store: open.store,
        keys: await open.keys.setPassphrase('a passphrase for backups'),
        file: backup,
        backupId: 'b1',
        createdAt: DateTime.utc(2026, 11, 3, 13, 3),
        files: {'r1.etr': photo},
      );
      from.lock();
    });
    tearDown(() => source.deleteSync(recursive: true));

    test('a backup opens with its recovery code or passphrase, not the app '
        'password, then asks for a password here (SEC-02, SEC-04)', () async {
      final phone = startup();
      await expectLater(
        phone.restore(backup.path, 'the other password'),
        throwsA(const KeyringException(KeyringError.wrongSecret)),
      );
      expect(phone.state, isA<NeedsSetup>());
      await phone.restore(backup.path, code, recovery: true);
      expect(phone.state, isA<Ready>());
      expect(phone.needsNewPassword, isTrue);
      expect(
        File('${directory.path}/receipts/r1.etr').readAsStringSync(),
        'photo',
      );
      await phone.setNewPassword('a password for this phone');
      phone.lock();
      final again = startup();
      await again.unlockWithPassword('a password for this phone');
      again.lock();
    });

    test('a restore goes on from above the revision the app layer knows '
        'delivered (review 28)', () async {
      final phone = startup();
      // The backup holds a few writes, far below the 57 delivered: the
      // book restored stands at 57 + 1.
      await phone.restore(
        backup.path,
        'a passphrase for backups',
        revisionAtLeast: 57,
      );
      expect((phone.state as Ready).vault.store.revision, 58);
      phone.lock();
    });

    test('the backup passphrase restores it too', () async {
      final phone = startup();
      await phone.restore(backup.path, 'a passphrase for backups');
      expect(phone.needsNewPassword, isTrue);
      phone.lock();
    });

    test('photos of a restore that fails stay as they were (SEC-09)', () async {
      final phone = startup();
      await phone.setUp(password);
      phone.lock();
      final mine = File('${directory.path}/receipts/r1.etr')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('mine');
      // The backup cut short after its photo: read up to there, then
      // refused.
      final bytes = backup.readAsBytesSync();
      var at = 8;
      var last = at;
      while (at < bytes.length) {
        last = at;
        at += 4 + ByteData.sublistView(bytes, at, at + 4).getUint32(0);
      }
      final cut = File('${source.path}/cut.etbk')
        ..writeAsBytesSync(bytes.sublist(0, last));
      final refused = await phone
          .restore(cut.path, code, recovery: true)
          .then<Object?>((_) => null, onError: (Object error) => error);
      expect(
        refused,
        isA<BackupException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.invalidFormat,
        ),
      );
      // What the restore form then says (review 16: a refused restore end
      // to end).
      expect(
        describeUnlockFailure(refused!, recovery: true),
        '這個檔案不是完整的記帳本備份，可能已損毀或沒有下載完',
      );
      expect(mine.readAsStringSync(), 'mine');
      expect(
        Directory('${directory.path}/files.restore').existsSync(),
        isFalse,
      );
    });
  });

  group('resetting the keys (SEC-06)', () {
    test(
      'a ledger with a password: new keys, the same records, a new code',
      () async {
        final first = startup();
        final code = await first.setUp(password);
        final oldKeyring = File('${directory.path}/keyring.json')
            .readAsStringSync();
        final before = (first.state as Ready).vault;
        before.store.write((w) => w.put('entry', 'e1', '{"amount":1}'));
        await expectLater(
          first.resetKeys(password: 'not it'),
          throwsA(const KeyringException(KeyringError.wrongSecret)),
        );
        await first.resetKeys(password: password);
        final after = (first.state as Ready).vault;
        expect(after, isNot(same(before)));
        expect(after.store.count, 1);
        expect(first.takeKeysReset(), isTrue);
        final newCode = first.takeRecoveryCode();
        expect(newCode, isNotNull);
        expect(newCode, isNot(code));
        first.lock();

        // The old keyring and password give a key that no longer opens it.
        final stale = await vault.codec.unlockWithPassword(
          Keyring.parse(oldKeyring),
          password,
        );
        expect(
          () => EncryptedDatabase.open(
            vault.databaseFile,
            StorageKey(stale.databaseKey),
          ),
          throwsA(const StorageUnavailable(StorageProblem.wrongKey)),
        );
        final again = startup();
        await again.unlockWithPassword(password);
        again.lock();
        final byCode = startup();
        await expectLater(
          byCode.unlockWithRecovery(code),
          throwsA(const KeyringException(KeyringError.wrongSecret)),
        );
        await byCode.unlockWithRecovery(newCode!);
        byCode.lock();
      },
    );

    test('a ledger without a password gets a new sealed key', () async {
      final first = startup();
      await first.setUpWithoutPassword();
      final oldSecret = await first.quickSecret();
      await first.resetKeys();
      expect(await first.quickSecret(), isNot(oldSecret));
      expect(
        File('${directory.path}/quick-open.sealed.next').existsSync(),
        isFalse,
      );
      first.lock();
      final again = startup();
      await again.openQuietly();
      expect(again.state, isA<Ready>());
      again.lock();
    });
  });

  test('ledgers kept before a restore are named and ordered by when their '
      'backups were taken, not the file\'s time (F91)', () async {
    final first = startup();
    await first.setUp(password);
    final open = (first.state as Ready).vault;
    final kept = first.beforeRestore..createSync(recursive: true);
    for (final (name, at) in [
      ('brought-back-1.etbk', DateTime.utc(2026, 11, 15, 2, 31)),
      ('記帳本-20261101.etbk', DateTime.utc(2026, 11, 1)),
    ]) {
      await LedgerBackup.write(
        store: open.store,
        keys: open.keys,
        file: File('${kept.path}/$name'),
        backupId: name,
        createdAt: at,
      );
    }
    // A copy Android brought back keeps a time near 1970.
    File('${kept.path}/brought-back-1.etbk')
        .setLastModifiedSync(DateTime.utc(1970, 1, 22, 2, 31));
    final ledgers = await first.keptLedgers();
    expect(
      [for (final (_, header) in ledgers) header!.createdAt],
      [DateTime.utc(2026, 11, 15, 2, 31), DateTime.utc(2026, 11, 1)],
    );
    first.lock();
  });
}
