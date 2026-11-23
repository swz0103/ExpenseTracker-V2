import 'dart:convert';

import 'package:test/test.dart';
import 'package:vault/backup_security.dart';

Matcher _fails(KeyringError error) => throwsA(KeyringException(error));

void main() {
  const password = 'correct horse battery';
  const passphrase = 'a passphrase for backups';
  final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);
  late CreatedKeyring created;

  setUpAll(() async => created = await codec.create(password));

  Keyring reread(Keyring keyring) => Keyring.parse(keyring.encode());

  test('a keyring without a passphrase keeps the first layout', () {
    final json = jsonDecode(created.keyring.encode()) as Map<String, Object?>;
    expect(json['version'], 1);
    expect(json.containsKey('passphrase'), isFalse);
    expect(created.keyring.hasPassword, isTrue);
    expect(created.keyring.hasPassphrase, isFalse);
  });

  test('a backup passphrase opens the same keys, held to the policy', () async {
    await expectLater(
      created.unlocked.setPassphrase('short'),
      _fails(KeyringError.weakPassword),
    );
    final withPassphrase = await created.unlocked.setPassphrase(passphrase);
    final keyring = reread(withPassphrase.keyring);
    expect(keyring.hasPassphrase, isTrue);
    final json = jsonDecode(keyring.encode()) as Map<String, Object?>;
    expect(json['version'], 2);
    final opened = await codec.unlockWithPassphrase(keyring, passphrase);
    expect(opened.databaseKey, created.unlocked.databaseKey);
    // Each secret opens only its own slot.
    await expectLater(
      codec.unlockWithPassphrase(keyring, password),
      _fails(KeyringError.wrongSecret),
    );
    await expectLater(
      codec.unlockWithPassword(keyring, passphrase),
      _fails(KeyringError.wrongSecret),
    );
    final dropped = reread(opened.removePassphrase().keyring);
    expect(dropped.hasPassphrase, isFalse);
    await expectLater(
      codec.unlockWithPassphrase(dropped, passphrase),
      _fails(KeyringError.noSuchSlot),
    );
  });

  test('the exported keyring has no password or device slot', () async {
    final withPassphrase = await created.unlocked.setPassphrase(passphrase);
    final exported = reread(withPassphrase.keyring.exported);
    final json = jsonDecode(exported.encode()) as Map<String, Object?>;
    expect(json['password'], isNull);
    expect(json['devices'], isEmpty);
    expect(exported.hasPassword, isFalse);
    await expectLater(
      codec.unlockWithPassword(exported, password),
      _fails(KeyringError.noSuchSlot),
    );
    final byCode = await codec.unlockWithRecovery(
      exported,
      created.recoveryCode,
    );
    final byPassphrase = await codec.unlockWithPassphrase(exported, passphrase);
    for (final opened in [byCode, byPassphrase]) {
      expect(opened.databaseKey, created.unlocked.databaseKey);
      expect(opened.backupKey(1), created.unlocked.backupKey(1));
    }
    // A password set on it afterwards (a restored ledger) brings the first
    // layout back.
    final bare = await codec.unlockWithRecovery(
      reread(created.keyring.exported),
      created.recoveryCode,
    );
    expect(
      (jsonDecode(bare.keyring.encode()) as Map<String, Object?>)['version'],
      2,
    );
    final restored = await bare.changePassword('a password for here');
    expect(
      (jsonDecode(restored.keyring.encode())
          as Map<String, Object?>)['version'],
      1,
    );
  });

  test('the second layout is never written for what the first holds', () {
    final json = jsonDecode(created.keyring.encode()) as Map<String, Object?>;
    final widened = {...json, 'version': 2, 'passphrase': null};
    expect(
      () => Keyring.parse(jsonEncode(widened)),
      throwsA(const KeyringException(KeyringError.invalidFormat)),
    );
  });

  test('a recovery code is told from a password by its prefix', () {
    expect(looksLikeRecoveryCode(created.recoveryCode), isTrue);
    expect(looksLikeRecoveryCode(' etr1 abcd'), isTrue);
    expect(looksLikeRecoveryCode(password), isFalse);
  });

  group('reset', () {
    test('every key is new; the old keyring opens only the old ones', () async {
      final withDevice = created.unlocked;
      final reset = await withDevice.reset(password: password);
      final next = reread(reset.unlocked.keyring);
      expect(next.id, created.keyring.id);
      expect(reset.recoveryCode, isNot(created.recoveryCode));
      expect(reset.unlocked.databaseKey, isNot(created.unlocked.databaseKey));
      // One more backup epoch; the earlier one still opens old backups.
      expect(next.currentBackupEpoch, created.keyring.currentBackupEpoch + 1);
      final byPassword = await codec.unlockWithPassword(next, password);
      expect(byPassword.databaseKey, reset.unlocked.databaseKey);
      expect(byPassword.backupKey(1), created.unlocked.backupKey(1));
      expect(byPassword.backupKey(2), isNot(created.unlocked.backupKey(1)));
      final byCode = await codec.unlockWithRecovery(next, reset.recoveryCode);
      expect(byCode.databaseKey, reset.unlocked.databaseKey);
      await expectLater(
        codec.unlockWithRecovery(next, created.recoveryCode),
        _fails(KeyringError.wrongSecret),
      );
      // The keyring kept before (as in an older backup) with the old
      // password gives the old database key, not the one in use now.
      final old = await codec.unlockWithPassword(created.keyring, password);
      expect(old.databaseKey, isNot(reset.unlocked.databaseKey));
    });

    test('the password in use is kept even when below the policy', () async {
      final legacy = await KeyringCodec(
        kdf: PasswordKdf.insecureForTests,
        minimumPassword: 6,
      ).create('123456');
      final opened = await codec.unlockWithPassword(legacy.keyring, '123456');
      final reset = await opened.reset(password: '123456');
      final again = await codec.unlockWithPassword(
        reread(reset.unlocked.keyring),
        '123456',
      );
      expect(again.databaseKey, reset.unlocked.databaseKey);
    });

    test('devices and the passphrase are dropped', () async {
      final withPassphrase = await created.unlocked.setPassphrase(passphrase);
      final reset = await withPassphrase.reset(password: password);
      expect(reset.unlocked.keyring.hasPassphrase, isFalse);
      expect(reset.unlocked.keyring.deviceIds, isEmpty);
      expect('$reset', isNot(contains(reset.recoveryCode)));
    });
  });
}
