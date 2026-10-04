import 'dart:convert';

import 'package:backup_security/backup_security.dart';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

/// Stands in for an Android Keystore key bound to one device.
final class _FakeDevice implements DeviceKeyWrapper {
  _FakeDevice(this._key);

  final List<int> _key;
  final _cipher = AesGcm.with256bits();

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) async {
    final box = await _cipher.encrypt(
      secret,
      secretKey: SecretKey(_key),
      aad: context,
    );
    return box.concatenation();
  }

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) {
    final box = SecretBox.fromConcatenation(
      wrapped,
      nonceLength: 12,
      macLength: 16,
    );
    return _cipher.decrypt(box, secretKey: SecretKey(_key), aad: context);
  }
}

Matcher _fails(KeyringError error) => throwsA(KeyringException(error));

void main() {
  const password = 'correct horse battery';
  final codec = KeyringCodec(kdf: PasswordKdf.insecureForTests);
  final device = _FakeDevice(List.filled(32, 7));
  late CreatedKeyring created;

  setUpAll(() async {
    created = await codec.create(password);
  });

  Keyring stored() => Keyring.parse(created.keyring.encode());

  test('every slot opens the same keys', () async {
    final withDevice = await created.unlocked.addDevice('pixel-8', device);
    final keyring = Keyring.parse(withDevice.keyring.encode());
    final byPassword = await codec.unlockWithPassword(keyring, password);
    final byRecovery = await codec.unlockWithRecovery(
      keyring,
      created.recoveryCode,
    );
    final byDevice = await codec.unlockWithDevice(keyring, 'pixel-8', device);
    for (final unlocked in [byPassword, byRecovery, byDevice]) {
      expect(unlocked.databaseKey, created.unlocked.databaseKey);
      expect(unlocked.backupKey(1), created.unlocked.backupKey(1));
    }
    expect(created.unlocked.databaseKey, hasLength(32));
    expect(created.unlocked.databaseKey, isNot(created.unlocked.backupKey(1)));
  });

  test('wrong secrets are refused', () async {
    await expectLater(
      codec.unlockWithPassword(stored(), 'wrong horse battery'),
      _fails(KeyringError.wrongSecret),
    );
    final other = await codec.create(password);
    await expectLater(
      codec.unlockWithRecovery(stored(), other.recoveryCode),
      _fails(KeyringError.wrongSecret),
    );
    final withDevice = await created.unlocked.addDevice('pixel-8', device);
    await expectLater(
      codec.unlockWithDevice(
        withDevice.keyring,
        'pixel-8',
        _FakeDevice(List.filled(32, 8)),
      ),
      _fails(KeyringError.wrongSecret),
    );
    await expectLater(
      codec.unlockWithDevice(withDevice.keyring, 'other', device),
      _fails(KeyringError.unknownDevice),
    );
  });

  test('recovery codes tolerate typing and catch typos', () async {
    final code = created.recoveryCode;
    expect(code, matches(RegExp(r'^ETR1(-[0-9A-HJKMNP-TV-Z]{4}){14}$')));
    final relaxed = code.toLowerCase().replaceAll('-', ' ');
    final opened = await codec.unlockWithRecovery(stored(), relaxed);
    expect(opened.databaseKey, created.unlocked.databaseKey);
    final last = code[code.length - 1];
    final typo = code.substring(0, code.length - 1) + (last == '0' ? '1' : '0');
    await expectLater(
      decodeRecoveryCode(typo),
      _fails(KeyringError.invalidFormat),
    );
    await expectLater(
      decodeRecoveryCode('ETR1-0000'),
      _fails(KeyringError.invalidFormat),
    );
  });

  test('passwords are compared after NFC normalization', () async {
    final composed = await codec.create('café au lait 2026');
    final opened = await codec.unlockWithPassword(
      composed.keyring,
      'café au lait 2026',
    );
    expect(opened.databaseKey, composed.unlocked.databaseKey);
  });

  test('short passwords are refused', () async {
    await expectLater(codec.create('short'), _fails(KeyringError.weakPassword));
    await expectLater(
      created.unlocked.changePassword('short'),
      _fails(KeyringError.weakPassword),
    );
  });

  test('changing the password rewrites only the password slot', () async {
    final changed = await created.unlocked.changePassword('a new passphrase');
    final keyring = Keyring.parse(changed.keyring.encode());
    await expectLater(
      codec.unlockWithPassword(keyring, password),
      _fails(KeyringError.wrongSecret),
    );
    final opened = await codec.unlockWithPassword(keyring, 'a new passphrase');
    expect(opened.databaseKey, created.unlocked.databaseKey);
    final recovered = await codec.unlockWithRecovery(
      keyring,
      created.recoveryCode,
    );
    expect(recovered.databaseKey, created.unlocked.databaseKey);
  });

  test('rotating the recovery code retires the old one', () async {
    final rotated = await created.unlocked.rotateRecovery();
    final keyring = Keyring.parse(rotated.unlocked.keyring.encode());
    expect(rotated.recoveryCode, isNot(created.recoveryCode));
    await expectLater(
      codec.unlockWithRecovery(keyring, created.recoveryCode),
      _fails(KeyringError.wrongSecret),
    );
    final opened = await codec.unlockWithRecovery(
      keyring,
      rotated.recoveryCode,
    );
    expect(opened.databaseKey, created.unlocked.databaseKey);
  });

  test('backup key rotation keeps older epochs readable', () async {
    final first = created.unlocked.backupKey(1);
    final rotated = await created.unlocked.rotateBackupKey();
    expect(rotated.currentBackupEpoch, 2);
    final keyring = Keyring.parse(rotated.keyring.encode());
    expect(keyring.currentBackupEpoch, 2);
    final opened = await codec.unlockWithPassword(keyring, password);
    expect(opened.backupKey(1), first);
    expect(opened.backupKey(2), rotated.backupKey(2));
    expect(opened.backupKey(2), isNot(first));
    expect(() => opened.backupKey(3), throwsRangeError);
  });

  test('devices can be added and removed', () async {
    final added = await created.unlocked.addDevice('pixel-8', device);
    expect(added.keyring.deviceIds, ['pixel-8']);
    await expectLater(
      added.addDevice('pixel-8', device),
      _fails(KeyringError.unknownDevice),
    );
    final removed = added.removeDevice('pixel-8');
    expect(removed.keyring.deviceIds, isEmpty);
    expect(
      () => removed.removeDevice('pixel-8'),
      throwsA(const KeyringException(KeyringError.unknownDevice)),
    );
  });

  test('boxes are bound to their slot and keyring', () async {
    final json = jsonDecode(created.keyring.encode()) as Map<String, Object?>;
    final swapped = Map.of(json)..['recovery'] = json['database'];
    await expectLater(
      codec.unlockWithRecovery(
        Keyring.parse(jsonEncode(swapped)),
        created.recoveryCode,
      ),
      _fails(KeyringError.wrongSecret),
    );
    final moved = Map.of(json)..['id'] = 'f' * 32;
    await expectLater(
      codec.unlockWithPassword(Keyring.parse(jsonEncode(moved)), password),
      _fails(KeyringError.wrongSecret),
    );
  });

  test('a keyring from another password policy is refused', () async {
    await expectLater(
      KeyringCodec().unlockWithPassword(stored(), password),
      _fails(KeyringError.unsupportedVersion),
    );
  });

  test('malformed keyrings are rejected before any crypto', () {
    final json = jsonDecode(created.keyring.encode()) as Map<String, Object?>;
    final cases = <Object?>[
      'not json',
      [],
      {...json, 'extra': 1},
      {...json, 'version': 2},
      {...json, 'id': 'ABC'},
      {...json, 'backupKeys': []},
      {...json, 'devices': 'none'},
      {
        ...json,
        'recovery': {'nonce': 'AAAA', 'box': 'AAAA'},
      },
    ];
    for (final value in cases) {
      final text = value is String ? value : jsonEncode(value);
      // Only another format version is unsupported; anything else is
      // malformed.
      final newer = value is Map && value['version'] == 2;
      expect(
        () => Keyring.parse(text),
        _fails(
          newer ? KeyringError.unsupportedVersion : KeyringError.invalidFormat,
        ),
        reason: text.length > 60 ? text.substring(0, 60) : text,
      );
    }
    expect(
      () => Keyring.parse('x' * (300 * 1024)),
      throwsA(const KeyringException(KeyringError.invalidFormat)),
    );
  });

  test('plaintext keys never appear in descriptions', () {
    final unlocked = created.unlocked;
    final hex = unlocked.databaseKey
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    expect('$unlocked', isNot(contains(hex)));
    expect('$created', isNot(contains(created.recoveryCode)));
    expect(created.keyring.encode(), isNot(contains(created.recoveryCode)));
  });
}
