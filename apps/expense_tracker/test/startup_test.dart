import 'dart:io';

import 'package:expense_tracker/src/startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

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
    expect(startup.takeRecoveryCode(), isNull);

    startup.lock();
    final again = Startup(vault);
    expect(again.state, isA<Locked>());
    expect(again.passwordless, isTrue);
    await again.openQuietly();
    expect(again.state, isA<Ready>());
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
