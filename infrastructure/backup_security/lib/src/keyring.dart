import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'errors.dart';
import 'recovery_code.dart';

const _format = 'ExpenseTracker-keyring';
const _version = 1;
const _maxKeyringCharacters = 256 * 1024;
const _maxDevices = 8;
const _maxBackupEpochs = 1000;
const _maxDeviceBox = 1024;
final _deviceId = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');

/// Argon2id parameters for the password slot. The id is stored in the
/// keyring and must match exactly; parameters are never read from the file.
final class PasswordKdf {
  const PasswordKdf._(this.memory, this.iterations);

  /// OWASP baseline: 19 MiB, 2 passes, 1 lane.
  static const standard = PasswordKdf._(19456, 2);

  /// Cheap parameters for tests. A keyring written with them is refused by a
  /// codec using [standard].
  static const insecureForTests = PasswordKdf._(256, 1);

  final int memory;
  final int iterations;

  String get id => 'argon2id-v19-m$memory-t$iterations-p1-k32';
}

/// Wraps secrets with a hardware key, for example an Android Keystore key
/// that requires biometric confirmation. [context] must be bound into the
/// wrapping so a blob cannot be moved to another slot.
abstract interface class DeviceKeyWrapper {
  Future<List<int>> wrap(List<int> secret, List<int> context);

  /// Throws if the blob was not produced by this device for [context].
  Future<List<int>> unwrap(List<int> wrapped, List<int> context);
}

final class _Box {
  const _Box(this.nonce, this.data);

  final List<int> nonce;

  /// Ciphertext followed by the 16-byte GCM tag.
  final List<int> data;

  Map<String, Object> toJson() => {
    'nonce': base64.encode(nonce),
    'box': base64.encode(data),
  };
}

final class _PasswordSlot {
  const _PasswordSlot(this.salt, this.box);

  final List<int> salt;
  final _Box box;
}

final class _DeviceSlot {
  const _DeviceSlot(this.id, this.blob);

  final String id;
  final List<int> blob;
}

/// The stored key hierarchy. It holds only wrapped keys and is safe to keep
/// next to the database or inside a backup.
///
/// A random master key is wrapped by every unlock slot (password, recovery
/// code, devices). The master key wraps the database key and each backup
/// key epoch, so changing a password or recovery code rewrites one slot and
/// never touches the data.
final class Keyring {
  const Keyring._({
    required this.id,
    required this.kdf,
    required _PasswordSlot password,
    required _Box recovery,
    required List<_DeviceSlot> devices,
    required _Box database,
    required List<_Box> backupKeys,
  }) : _password = password,
       _recovery = recovery,
       _devices = devices,
       _database = database,
       _backupKeys = backupKeys;

  /// Parses and validates a stored keyring. Any deviation from the exact
  /// layout is [KeyringError.invalidFormat].
  factory Keyring.parse(String text) {
    if (text.length > _maxKeyringCharacters) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    final root = _object(decoded, const {
      'format',
      'version',
      'id',
      'kdf',
      'password',
      'recovery',
      'devices',
      'database',
      'backupKeys',
    });
    if (root['format'] != _format || root['version'] != _version) {
      throw const KeyringException(KeyringError.unsupportedVersion);
    }
    final id = root['id'];
    final kdf = root['kdf'];
    if (id is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    if (kdf is! String || kdf.length > 64) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    final password = _object(root['password'], const {'salt', 'nonce', 'box'});
    final devices = root['devices'];
    final epochs = root['backupKeys'];
    if (devices is! List || devices.length > _maxDevices) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    if (epochs is! List || epochs.isEmpty || epochs.length > _maxBackupEpochs) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    final deviceSlots = [
      for (final device in devices) _readDevice(device),
    ];
    if (deviceSlots.map((slot) => slot.id).toSet().length !=
        deviceSlots.length) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    return Keyring._(
      id: id,
      kdf: kdf,
      password: _PasswordSlot(
        _bytes(password['salt'], 16),
        _readBox(password, const {'salt', 'nonce', 'box'}),
      ),
      recovery: _readBox(root['recovery']),
      devices: List.unmodifiable(deviceSlots),
      database: _readBox(root['database']),
      backupKeys: List.unmodifiable([
        for (var i = 0; i < epochs.length; i++) _readEpoch(epochs[i], i + 1),
      ]),
    );
  }

  final String id;
  final String kdf;
  final _PasswordSlot _password;
  final _Box _recovery;
  final List<_DeviceSlot> _devices;
  final _Box _database;
  final List<_Box> _backupKeys;

  List<String> get deviceIds => [for (final slot in _devices) slot.id];

  int get currentBackupEpoch => _backupKeys.length;

  String encode() => jsonEncode({
    'format': _format,
    'version': _version,
    'id': id,
    'kdf': kdf,
    'password': {
      'salt': base64.encode(_password.salt),
      ..._password.box.toJson(),
    },
    'recovery': _recovery.toJson(),
    'devices': [
      for (final slot in _devices)
        {'id': slot.id, 'blob': base64.encode(slot.blob)},
    ],
    'database': _database.toJson(),
    'backupKeys': [
      for (var i = 0; i < _backupKeys.length; i++)
        {'epoch': i + 1, ..._backupKeys[i].toJson()},
    ],
  });

  Keyring _copyWith({
    _PasswordSlot? password,
    _Box? recovery,
    List<_DeviceSlot>? devices,
    List<_Box>? backupKeys,
  }) => Keyring._(
    id: id,
    kdf: kdf,
    password: password ?? _password,
    recovery: recovery ?? _recovery,
    devices: List.unmodifiable(devices ?? _devices),
    database: _database,
    backupKeys: List.unmodifiable(backupKeys ?? _backupKeys),
  );

  static _DeviceSlot _readDevice(Object? value) {
    final device = _object(value, const {'id', 'blob'});
    final id = device['id'];
    if (id is! String || !_deviceId.hasMatch(id)) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    return _DeviceSlot(id, _bytes(device['blob'], null));
  }

  static _Box _readEpoch(Object? value, int epoch) {
    final keys = const {'epoch', 'nonce', 'box'};
    final entry = _object(value, keys);
    if (entry['epoch'] != epoch) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    return _readBox(entry, keys);
  }

  static _Box _readBox(
    Object? value, [
    Set<String> keys = const {'nonce', 'box'},
  ]) {
    final box = _object(value, keys);
    return _Box(_bytes(box['nonce'], 12), _bytes(box['box'], 48));
  }

  static Map<String, Object?> _object(Object? value, Set<String> keys) {
    if (value is! Map<String, Object?> ||
        value.length != keys.length ||
        !keys.containsAll(value.keys)) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    return value;
  }

  /// Decodes canonical base64 of exactly [length] bytes, or of at most
  /// [_maxDeviceBox] bytes when [length] is null.
  static List<int> _bytes(Object? value, int? length) {
    if (value is! String || value.length > _maxDeviceBox * 2) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    final List<int> bytes;
    try {
      bytes = base64.decode(value);
    } on FormatException {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    final sizeOk = length == null
        ? bytes.isNotEmpty && bytes.length <= _maxDeviceBox
        : bytes.length == length;
    if (!sizeOk || base64.encode(bytes) != value) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    return List.unmodifiable(bytes);
  }
}

final class CreatedKeyring {
  const CreatedKeyring(this.unlocked, this.recoveryCode);

  final UnlockedKeyring unlocked;

  /// Shown to the person once. It is never stored.
  final String recoveryCode;

  Keyring get keyring => unlocked.keyring;

  @override
  String toString() => 'CreatedKeyring(redacted)';
}

final class RotatedRecovery {
  const RotatedRecovery(this.unlocked, this.recoveryCode);

  final UnlockedKeyring unlocked;
  final String recoveryCode;

  @override
  String toString() => 'RotatedRecovery(redacted)';
}

/// Creates and opens keyrings.
final class KeyringCodec {
  KeyringCodec({this.kdf = PasswordKdf.standard, this.minimumPassword = 12});

  final PasswordKdf kdf;

  /// Minimum length in Unicode code points after NFC normalization.
  final int minimumPassword;

  final _cipher = AesGcm.with256bits();
  final _random = Random.secure();

  Future<CreatedKeyring> create(String password) async {
    final normalized = _checkedPassword(password);
    final id = _hex(_randomBytes(16));
    final master = _randomBytes(32);
    final recoveryKey = _randomBytes(32);
    final salt = _randomBytes(16);
    final keyring = Keyring._(
      id: id,
      kdf: kdf.id,
      password: _PasswordSlot(
        salt,
        await _seal(await _derive(normalized, salt), master, id, 'password'),
      ),
      recovery: await _seal(recoveryKey, master, id, 'recovery'),
      devices: const [],
      database: await _seal(master, _randomBytes(32), id, 'database'),
      backupKeys: List.unmodifiable([
        await _seal(master, _randomBytes(32), id, 'backup:1'),
      ]),
    );
    return CreatedKeyring(
      await _unlocked(keyring, master),
      await encodeRecoveryCode(recoveryKey),
    );
  }

  Future<UnlockedKeyring> unlockWithPassword(
    Keyring keyring,
    String password,
  ) async {
    if (keyring.kdf != kdf.id) {
      throw const KeyringException(KeyringError.unsupportedVersion);
    }
    final slot = keyring._password;
    final key = await _derive(unorm.nfc(password), slot.salt);
    final master = await _open(key, slot.box, keyring.id, 'password');
    return _unlocked(keyring, master);
  }

  Future<UnlockedKeyring> unlockWithRecovery(
    Keyring keyring,
    String recoveryCode,
  ) async {
    final key = await decodeRecoveryCode(recoveryCode);
    final master = await _open(key, keyring._recovery, keyring.id, 'recovery');
    return _unlocked(keyring, master);
  }

  Future<UnlockedKeyring> unlockWithDevice(
    Keyring keyring,
    String deviceId,
    DeviceKeyWrapper wrapper,
  ) async {
    final slot = keyring._devices.where((slot) => slot.id == deviceId);
    if (slot.isEmpty) {
      throw const KeyringException(KeyringError.unknownDevice);
    }
    final List<int> master;
    try {
      master = await wrapper.unwrap(
        slot.single.blob,
        _aad(keyring.id, 'device:$deviceId'),
      );
    } catch (_) {
      throw const KeyringException(KeyringError.wrongSecret);
    }
    if (master.length != 32) {
      throw const KeyringException(KeyringError.wrongSecret);
    }
    return _unlocked(keyring, master);
  }

  /// Every wrapped key is opened here, so a keyring whose database or backup
  /// boxes were swapped or damaged fails at unlock instead of later.
  Future<UnlockedKeyring> _unlocked(Keyring keyring, List<int> master) async {
    final database = await _open(
      master,
      keyring._database,
      keyring.id,
      'database',
    );
    final backupKeys = <Uint8List>[];
    for (var i = 0; i < keyring._backupKeys.length; i++) {
      backupKeys.add(
        await _open(
          master,
          keyring._backupKeys[i],
          keyring.id,
          'backup:${i + 1}',
        ),
      );
    }
    return UnlockedKeyring._(
      this,
      keyring,
      Uint8List.fromList(master),
      database,
      backupKeys,
    );
  }

  String _checkedPassword(String password) {
    final normalized = unorm.nfc(password);
    if (normalized.runes.length < minimumPassword) {
      throw const KeyringException(KeyringError.weakPassword);
    }
    return normalized;
  }

  Future<List<int>> _derive(String normalized, List<int> salt) async {
    final argon = Argon2id(
      memory: kdf.memory,
      iterations: kdf.iterations,
      parallelism: 1,
      hashLength: 32,
    );
    final key = await argon.deriveKey(
      secretKey: SecretKey(utf8.encode(normalized)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  Future<_Box> _seal(
    List<int> key,
    List<int> secret,
    String keyringId,
    String purpose,
  ) async {
    final box = await _cipher.encrypt(
      secret,
      secretKey: SecretKey(key),
      aad: _aad(keyringId, purpose),
    );
    return _Box(
      List.unmodifiable(box.nonce),
      List.unmodifiable([...box.cipherText, ...box.mac.bytes]),
    );
  }

  Future<Uint8List> _open(
    List<int> key,
    _Box box,
    String keyringId,
    String purpose,
  ) async {
    final split = box.data.length - 16;
    final secretBox = SecretBox(
      box.data.sublist(0, split),
      nonce: box.nonce,
      mac: Mac(box.data.sublist(split)),
    );
    try {
      final clear = await _cipher.decrypt(
        secretBox,
        secretKey: SecretKey(key),
        aad: _aad(keyringId, purpose),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const KeyringException(KeyringError.wrongSecret);
    }
  }

  Uint8List _randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));
}

/// An opened keyring. Holds plaintext keys, so it never prints them and
/// should be dropped when the app locks.
final class UnlockedKeyring {
  UnlockedKeyring._(
    this._codec,
    this.keyring,
    this._master,
    this._database,
    this._backupKeys,
  );

  final KeyringCodec _codec;
  final Keyring keyring;
  final Uint8List _master;
  final Uint8List _database;
  final List<Uint8List> _backupKeys;

  /// The 32-byte SQLCipher key. It never changes for the life of the
  /// database; only the slots around it rotate.
  Uint8List get databaseKey => Uint8List.fromList(_database);

  int get currentBackupEpoch => _backupKeys.length;

  /// The key for backups written in [epoch]; older epochs stay readable.
  Uint8List backupKey(int epoch) {
    RangeError.checkValueInInterval(epoch, 1, _backupKeys.length, 'epoch');
    return Uint8List.fromList(_backupKeys[epoch - 1]);
  }

  Future<UnlockedKeyring> changePassword(String newPassword) async {
    final normalized = _codec._checkedPassword(newPassword);
    final salt = _codec._randomBytes(16);
    final key = await _codec._derive(normalized, salt);
    final box = await _codec._seal(key, _master, keyring.id, 'password');
    return _next(keyring._copyWith(password: _PasswordSlot(salt, box)));
  }

  /// Replaces the recovery code; the previous code stops working.
  Future<RotatedRecovery> rotateRecovery() async {
    final key = _codec._randomBytes(32);
    final box = await _codec._seal(key, _master, keyring.id, 'recovery');
    return RotatedRecovery(
      _next(keyring._copyWith(recovery: box)),
      await encodeRecoveryCode(key),
    );
  }

  Future<UnlockedKeyring> addDevice(
    String deviceId,
    DeviceKeyWrapper wrapper,
  ) async {
    if (!_deviceId.hasMatch(deviceId) ||
        keyring.deviceIds.contains(deviceId) ||
        keyring._devices.length >= _maxDevices) {
      throw const KeyringException(KeyringError.unknownDevice);
    }
    final blob = await wrapper.wrap(
      _master,
      _aad(keyring.id, 'device:$deviceId'),
    );
    if (blob.isEmpty || blob.length > _maxDeviceBox) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    final slot = _DeviceSlot(deviceId, List.unmodifiable(blob));
    return _next(keyring._copyWith(devices: [...keyring._devices, slot]));
  }

  UnlockedKeyring removeDevice(String deviceId) {
    if (!keyring.deviceIds.contains(deviceId)) {
      throw const KeyringException(KeyringError.unknownDevice);
    }
    final devices = keyring._devices.where((slot) => slot.id != deviceId);
    return _next(keyring._copyWith(devices: devices.toList()));
  }

  /// Starts a new backup key epoch. New backups use the new key; backups
  /// from earlier epochs remain readable.
  Future<UnlockedKeyring> rotateBackupKey() async {
    if (_backupKeys.length >= _maxBackupEpochs) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    final epoch = _backupKeys.length + 1;
    final key = _codec._randomBytes(32);
    final box = await _codec._seal(_master, key, keyring.id, 'backup:$epoch');
    return UnlockedKeyring._(
      _codec,
      keyring._copyWith(backupKeys: [...keyring._backupKeys, box]),
      _master,
      _database,
      [..._backupKeys, key],
    );
  }

  UnlockedKeyring _next(Keyring next) =>
      UnlockedKeyring._(_codec, next, _master, _database, _backupKeys);

  @override
  String toString() => 'UnlockedKeyring(${keyring.id}, redacted)';
}

List<int> _aad(String keyringId, String purpose) =>
    utf8.encode('$_format/$_version/$keyringId/$purpose');

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
