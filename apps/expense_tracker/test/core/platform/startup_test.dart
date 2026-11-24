import 'dart:io';

import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart' show StorageProblem, StorageUnavailable;
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import 'startup_gate.dart';
import 'startup_keys.dart';

const password = 'correct horse battery';

/// Stands in for an Android Keystore key; a blob opens only for the
/// context it was wrapped with, as the real key requires.
final class FakeDeviceKey implements DeviceKeyWrapper {
  final _secrets = <String, (List<int>, List<int>)>{};

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) async {
    final handle = 'blob-${_secrets.length}';
    _secrets[handle] = (List.of(secret), List.of(context));
    return handle.codeUnits;
  }

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) async {
    final entry = _secrets[String.fromCharCodes(wrapped)];
    if (entry == null || !listEquals(entry.$2, context)) {
      throw StateError('not this device');
    }
    return entry.$1;
  }
}

void main() {
  group('keys', startupKeyTests);
  group('lock gate', startupGateTests);

  late Directory directory;
  late LedgerVault vault;
  final device = DeviceUnlock('phone-1', FakeDeviceKey());

  setUp(() {
    directory = Directory.systemTemp.createTempSync('startup-');
    vault = LedgerVault(
      directory,
      codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
    );
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('set up, lock, then unlock with the device key', () async {
    final startup = Startup(vault, device: device);
    expect(startup.state, isA<NeedsSetup>());
    final recovery = await startup.setUp(password);
    expect(recovery, isNotEmpty);
    final keyring = (startup.state as Ready).vault.keys.keyring.id;

    startup.lock();
    expect(startup.state, isA<Locked>());
    final reopened = Startup(vault, device: device);
    expect((reopened.state as Locked).deviceUnlock, isTrue);
    await reopened.unlockWithDevice();
    expect((reopened.state as Ready).vault.keys.keyring.id, keyring);
    reopened.lock();
  });

  test('a wrong password keeps the ledger locked', () async {
    final first = Startup(vault);
    await first.setUp(password);
    first.lock();
    final startup = Startup(vault);
    await expectLater(
      startup.unlockWithPassword('not the password'),
      throwsA(const KeyringException(KeyringError.wrongSecret)),
    );
    expect(startup.state, isA<Locked>());
    await startup.unlockWithPassword(password);
    expect(startup.state, isA<Ready>());
    startup.lock();
  });

  group('a damaged ledger file (D94)', () {
    Future<void> damage() async {
      final first = Startup(vault);
      await first.setUp(password);
      first.lock();
      vault.databaseFile.writeAsBytesSync(const []);
    }

    test('is told apart from a wrong password, set aside, and '
        'restored over', () async {
      await damage();
      final startup = Startup(vault);
      var told = 0;
      startup.addListener(() => told++);
      await expectLater(
        startup.unlockWithPassword(password),
        throwsA(const StorageUnavailable(StorageProblem.damaged)),
      );
      expect(startup.state, isA<Damaged>());
      expect(told, 1);
      expect(vault.databaseFile.existsSync(), isFalse);
      expect(vault.damagedCopies(), hasLength(1));

      // Tried again: still damaged, never an empty book.
      startup.retryAfterDamage();
      expect(startup.state, isA<Locked>());
      await expectLater(
        startup.unlockWithPassword(password),
        throwsA(const StorageUnavailable(StorageProblem.damaged)),
      );
      expect(startup.state, isA<Damaged>());
      expect(vault.databaseFile.existsSync(), isFalse);

      // Restoring is offered from there: the lock screen's backup form.
      startup.lockToRestore();
      expect(startup.state, isA<Locked>());
      expect(startup.takeRestore(), isTrue);
    });

    test('a wrong password is said as before', () async {
      await damage();
      final startup = Startup(vault);
      await expectLater(
        startup.unlockWithPassword('not the password'),
        throwsA(const KeyringException(KeyringError.wrongSecret)),
      );
      expect(startup.state, isA<Locked>());
      expect(vault.damagedCopies(), isEmpty);
    });

    test('reading the book passes on what it gives, and any other '
        'failure as it is', () async {
      final startup = Startup(vault);
      await startup.setUp(password);
      expect(await startup.readingBook(Future.value(7)), 7);
      await expectLater(
        startup.readingBook<int>(Future.error(StateError('other'))),
        throwsStateError,
      );
      await expectLater(
        startup.readingBook<int>(
          Future.error(const StorageUnavailable(StorageProblem.inUse)),
        ),
        throwsA(const StorageUnavailable(StorageProblem.inUse)),
      );
      expect(startup.state, isA<Ready>());
      await expectLater(
        startup.readingBook<int>(
          Future.error(const StorageUnavailable(StorageProblem.damaged)),
        ),
        throwsA(const StorageUnavailable(StorageProblem.damaged)),
      );
      expect(startup.state, isA<Damaged>());
      expect(vault.damagedCopies(), hasLength(1));
    });

    test('found as the book is read, it is closed and set aside', () async {
      final startup = Startup(vault);
      await startup.setUp(password);
      final open = (startup.state as Ready).vault;
      await startup.bookDamaged(
        const StorageUnavailable(StorageProblem.damaged),
      );
      expect(startup.state, isA<Damaged>());
      expect(open.store.isOpen, isFalse);
      expect(vault.databaseFile.existsSync(), isFalse);
      expect(vault.damagedCopies(), hasLength(1));
    });
  });

  test('a cancelled fingerprint does not stop the password unlock', () async {
    final first = Startup(vault);
    await first.setUp(password);
    first.lock();
    final startup = Startup(
      vault,
      device: DeviceUnlock('phone-2', _CancelledDeviceKey()),
    );
    await startup.unlockWithPassword(password);
    expect(startup.state, isA<Ready>());
    final keys = (startup.state as Ready).vault.keys.keyring;
    expect(keys.deviceIds, isNot(contains('phone-2')));
    startup.lock();
  });

  test('a ledger without a password opens by itself', () async {
    final startup = Startup(vault);
    await startup.setUpWithoutPassword();
    expect(startup.state, isA<Ready>());
    expect(startup.passwordless, isTrue);
    // Shown once: the copy Android takes to Google opens with it.
    expect(startup.takeRecoveryCode(), isNotNull);
    expect(startup.takeRecoveryCode(), isNull);
    expect(startup.recoveryGiven.existsSync(), isTrue);

    startup.lock();
    final again = Startup(vault);
    expect(again.state, isA<Locked>());
    expect(again.passwordless, isTrue);
    await again.openQuietly();
    expect(again.state, isA<Ready>());
  });

  test('a set-up without a password that stopped part way leaves no key '
      'for a ledger never made, and keeps the one for a ledger made', () async {
    final key = File('${directory.path}/quick-open.sealed');
    final pending = File('${key.path}.new');
    pending.writeAsStringSync('left over');
    final none = Startup(vault);
    expect(none.state, isA<NeedsSetup>());
    expect(none.passwordless, isFalse);
    expect(pending.existsSync(), isFalse);

    final made = Startup(vault);
    await made.setUpWithoutPassword();
    made.lock();
    key.renameSync(pending.path);
    final again = Startup(vault);
    expect(again.state, isA<Locked>());
    expect(again.passwordless, isTrue);
    await again.openQuietly();
    expect(again.state, isA<Ready>());
  });

  test('a password set-up drops a key left from an earlier try', () async {
    File('${directory.path}/quick-open.key').writeAsStringSync('old');
    final startup = Startup(vault);
    await startup.setUp(password);
    expect(startup.passwordless, isFalse);
  });

  test('a new ledger sets aside the copy Android brought back', () async {
    final startup = Startup(vault);
    final copy = startup.cloudCopy;
    await copy.parent.create(recursive: true);
    await copy.writeAsString('not a backup');
    expect(await startup.broughtBack(), isNull, reason: 'unreadable');
    await startup.setUpWithoutPassword();
    expect(copy.existsSync(), isFalse);
    expect(
      startup.beforeRestore.listSync().whereType<File>().single.path,
      contains('brought-back-'),
    );
    startup.lock();
  });

  test('a ledger without a password that never showed its code shows a '
      'new one once, as it opens', () async {
    final startup = Startup(vault);
    await startup.setUpWithoutPassword();
    startup
      ..takeRecoveryCode()
      ..lock();
    // As a ledger from before 0.5.1: no code was shown.
    startup.recoveryGiven.deleteSync();
    final again = Startup(vault);
    await again.openQuietly();
    final code = again.takeRecoveryCode();
    expect(code, isNotNull);
    again.lock();
    final third = Startup(vault);
    await third.openQuietly();
    expect(third.takeRecoveryCode(), isNull, reason: 'once');
    third.lock();
    // The new code opens it.
    final fourth = Startup(vault);
    await fourth.unlockWithRecovery(code!);
    expect(fourth.state, isA<Ready>());
    fourth.lock();
  });
}

/// A device key whose fingerprint prompt is always cancelled.
final class _CancelledDeviceKey implements DeviceKeyWrapper {
  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) =>
      Future.error(StateError('cancelled'));

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) =>
      Future.error(StateError('cancelled'));
}
