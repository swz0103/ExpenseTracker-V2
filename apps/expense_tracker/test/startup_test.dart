import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_security/backup_security.dart';
import 'package:expense_tracker/src/startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_vault/ledger_vault.dart';

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
    final ready = startup.state as Ready;
    final twd = Currency.of('TWD');
    await ready.session.openAccount(
      '現金',
      AccountKind.cash,
      Money(twd, BigInt.from(100)),
    );

    startup.lock();
    expect(startup.state, isA<Locked>());
    final reopened = Startup(vault, device: device);
    expect((reopened.state as Locked).deviceUnlock, isTrue);
    await reopened.unlockWithDevice();
    final session = (reopened.state as Ready).session;
    expect(session.accounts.single.name, '現金');
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
}
