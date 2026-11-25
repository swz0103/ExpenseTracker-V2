import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'errors.dart';
import 'password_policy.dart';
import 'recovery_code.dart';

const _format = 'ExpenseTracker-keyring';

/// The layout without a backup passphrase and with a password slot, which
/// every keyring had before backups stopped carrying the password.
const _version = 1;

/// The layout whose password slot may be empty (a keyring taken out in a
/// backup) and which may hold a backup passphrase slot. Written only when
/// the first layout cannot hold the keyring, so a keyring that fits it
/// stays byte for byte what older versions read.
const _versionWithPassphrase = 2;

/// Bound into every box's associated data. It names the first layout and
/// never changes, so boxes sealed then still open.
const _aadVersion = 1;
const _maxKeyringCharacters = 256 * 1024;
const _maxDevices = 8;
const _maxBackupEpochs = 1000;
const _maxDeviceBox = 1024;
final _deviceId = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');

/// Argon2id parameters for the password slot. The id is stored in the
/// keyring and must name parameters the app knows, the current ones or
/// one of [retired]; parameters are never read from the file.
final class PasswordKdf {
  const PasswordKdf._(this.memory, this.iterations);

  /// OWASP baseline: 19 MiB, 2 passes, 1 lane.
  static const standard = PasswordKdf._(19456, 2);

  /// The backup passphrase slot's parameters: 64 MiB, 2 passes, 1 lane.
  /// The passphrase travels in every backup's plain header, so whoever
  /// holds a backup file can guess it offline with no lockout; it is
  /// stretched harder than the password, which stays on the phone.
  /// Measured on the development VM (pure Dart, AOT): 0.6–0.75 s, against
  /// 0.17–0.27 s for [standard]; about 2 s on a mid-range phone at the
  /// usual factor of three. It runs only when the passphrase is set and
  /// when a backup is opened with it. Slots set before keep the id they
  /// name ([standard]) and still open.
  static const passphrase = PasswordKdf._(65536, 2);

  /// Cheap parameters for tests. A keyring written with them is refused by a
  /// codec using [standard].
  static const insecureForTests = PasswordKdf._(256, 1);

  /// Other cheap parameters, for tests of a keyring kept with parameters
  /// since retired.
  static const olderForTests = PasswordKdf._(128, 1);

  /// Parameters [standard] once was, newest first. A keyring that names
  /// one still opens with it, so a password set years ago keeps working;
  /// a password set now always takes the current ones. When [standard]
  /// changes, the old value is added here and never removed.
  static const List<PasswordKdf> retired = [];

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

/// A backup passphrase: its own Argon2id parameters, as it may be set at
/// another time than the password.
final class _PassphraseSlot {
  const _PassphraseSlot(this.kdf, this.salt, this.box);

  final String kdf;
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
/// code, backup passphrase, devices). The master key wraps the database key
/// and each backup key epoch, so changing a password or recovery code
/// rewrites one slot and never touches the data; [UnlockedKeyring.reset]
/// replaces the keys themselves.
final class Keyring {
  const Keyring._({
    required this.id,
    required this.kdf,
    required this._password,
    required this._passphrase,
    required this._recovery,
    required this._devices,
    required this._database,
    required this._backupKeys,
  });

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
    if (decoded is! Map<String, Object?>) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    if (decoded['format'] != _format) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    final version = decoded['version'];
    if (version != _version && version != _versionWithPassphrase) {
      throw const KeyringException(KeyringError.unsupportedVersion);
    }
    final second = version == _versionWithPassphrase;
    final root = _object(decoded, {
      'format',
      'version',
      'id',
      'kdf',
      'password',
      if (second) 'passphrase',
      'recovery',
      'devices',
      'database',
      'backupKeys',
    });
    final id = root['id'];
    final kdf = root['kdf'];
    if (id is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    if (kdf is! String || kdf.length > 64) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    final devices = root['devices'];
    final epochs = root['backupKeys'];
    if (devices is! List || devices.length > _maxDevices) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    if (epochs is! List || epochs.isEmpty || epochs.length > _maxBackupEpochs) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    final deviceSlots = [for (final device in devices) _readDevice(device)];
    if (deviceSlots.map((slot) => slot.id).toSet().length !=
        deviceSlots.length) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    final password = second && root['password'] == null
        ? null
        : _readPassword(root['password']);
    final passphrase = second && root['passphrase'] != null
        ? _readPassphrase(root['passphrase'])
        : null;
    if (second && password != null && passphrase == null) {
      // The first layout holds this keyring: it is never written so.
      throw const KeyringException(KeyringError.invalidFormat);
    }
    return Keyring._(
      id: id,
      kdf: kdf,
      password: password,
      passphrase: passphrase,
      recovery: _readBox(root['recovery']),
      devices: List.unmodifiable(deviceSlots),
      database: _readBox(root['database']),
      backupKeys: List.unmodifiable([
        for (var i = 0; i < epochs.length; i++) _readEpoch(epochs[i], i + 1),
      ]),
    );
  }

  final String id;

  /// The parameters of the password slot.
  final String kdf;
  final _PasswordSlot? _password;
  final _PassphraseSlot? _passphrase;
  final _Box _recovery;
  final List<_DeviceSlot> _devices;
  final _Box _database;
  final List<_Box> _backupKeys;

  List<String> get deviceIds => [for (final slot in _devices) slot.id];

  int get currentBackupEpoch => _backupKeys.length;

  /// Whether the app password opens this keyring. A keyring taken out in
  /// a backup has none ([exported]).
  bool get hasPassword => _password != null;

  /// Whether a backup passphrase opens this keyring.
  bool get hasPassphrase => _passphrase != null;

  /// This keyring as a backup carries it: without the password slot, which
  /// a short password would let anyone holding the file guess offline, and
  /// without the device slots, which open nothing elsewhere. The recovery
  /// code (256 bits) and the backup passphrase, held to the stricter
  /// [PasswordPolicy.passphrase] and stretched with
  /// [PasswordKdf.passphrase], still open it.
  Keyring get exported => Keyring._(
    id: id,
    kdf: kdf,
    password: null,
    passphrase: _passphrase,
    recovery: _recovery,
    devices: const [],
    database: _database,
    backupKeys: _backupKeys,
  );

  String encode() {
    final password = _password;
    final passphrase = _passphrase;
    final first = password != null && passphrase == null;
    return jsonEncode({
      'format': _format,
      'version': first ? _version : _versionWithPassphrase,
      'id': id,
      'kdf': kdf,
      'password': password == null
          ? null
          : {'salt': base64.encode(password.salt), ...password.box.toJson()},
      if (!first)
        'passphrase': passphrase == null
            ? null
            : {
                'kdf': passphrase.kdf,
                'salt': base64.encode(passphrase.salt),
                ...passphrase.box.toJson(),
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
  }

  Keyring _copyWith({
    String? kdf,
    _PasswordSlot? password,
    _PassphraseSlot? Function()? passphrase,
    _Box? recovery,
    List<_DeviceSlot>? devices,
    List<_Box>? backupKeys,
  }) => Keyring._(
    id: id,
    kdf: kdf ?? this.kdf,
    password: password ?? _password,
    passphrase: passphrase == null ? _passphrase : passphrase(),
    recovery: recovery ?? _recovery,
    devices: List.unmodifiable(devices ?? _devices),
    database: _database,
    backupKeys: List.unmodifiable(backupKeys ?? _backupKeys),
  );

  static _PasswordSlot _readPassword(Object? value) {
    const keys = {'salt', 'nonce', 'box'};
    final slot = _object(value, keys);
    return _PasswordSlot(_bytes(slot['salt'], 16), _readBox(slot, keys));
  }

  static _PassphraseSlot _readPassphrase(Object? value) {
    const keys = {'kdf', 'salt', 'nonce', 'box'};
    final slot = _object(value, keys);
    final kdf = slot['kdf'];
    if (kdf is! String || kdf.length > 64) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    return _PassphraseSlot(kdf, _bytes(slot['salt'], 16), _readBox(slot, keys));
  }

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

/// A keyring whose keys were all replaced ([UnlockedKeyring.reset]),
/// with its new recovery code, to show once.
final class ResetKeyring {
  const ResetKeyring(this.unlocked, this.recoveryCode);

  final UnlockedKeyring unlocked;
  final String recoveryCode;

  @override
  String toString() => 'ResetKeyring(redacted)';
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
  /// [minimumPassword], when given, replaces both policies with the rule
  /// before them (a length alone), for tools and tests that make the short
  /// passwords older versions allowed; the app sets every password under
  /// [PasswordPolicy.standard] and every backup passphrase under
  /// [PasswordPolicy.passphrase].
  ///
  /// [passphraseKdf] defaults to [PasswordKdf.passphrase] when [kdf] is
  /// [PasswordKdf.standard], and to [kdf] otherwise, so a codec made with
  /// cheap parameters for tests stretches passphrases cheaply too.
  KeyringCodec({
    this.kdf = PasswordKdf.standard,
    PasswordKdf? passphraseKdf,
    int? minimumPassword,
    this.retired = PasswordKdf.retired,
  }) : passphraseKdf =
           passphraseKdf ??
           (kdf == PasswordKdf.standard ? PasswordKdf.passphrase : kdf),
       policy = minimumPassword == null
           ? PasswordPolicy.standard
           : _older(minimumPassword),
       passphrasePolicy = minimumPassword == null
           ? PasswordPolicy.passphrase
           : _older(minimumPassword);

  static PasswordPolicy _older(int minimumLength) =>
      PasswordPolicy(minimumLength: minimumLength, digitsOnlyAllowed: true);

  /// The parameters a password is set with.
  final PasswordKdf kdf;

  /// The parameters a backup passphrase is set with.
  final PasswordKdf passphraseKdf;

  /// Parameters a keyring may still name, set before [kdf] took over.
  final List<PasswordKdf> retired;

  /// The parameters [id] names, if this codec reads them for a password.
  PasswordKdf? _readable(String id) => _named(id, [kdf, ...retired]);

  /// The parameters [id] names, if this codec reads them for a backup
  /// passphrase: its own, or any a password may name, as passphrases
  /// were once set with the password's.
  PasswordKdf? _readablePassphrase(String id) =>
      _named(id, [passphraseKdf, kdf, ...retired]);

  static PasswordKdf? _named(String id, List<PasswordKdf> known) {
    for (final params in known) {
      if (params.id == id) return params;
    }
    return null;
  }

  /// What a password must be to be set.
  final PasswordPolicy policy;

  /// What a backup passphrase must be to be set: stricter than [policy],
  /// as anyone holding a backup can guess it offline.
  final PasswordPolicy passphrasePolicy;

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
      passphrase: null,
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
    final params = _readable(keyring.kdf);
    if (params == null) {
      throw const KeyringException(KeyringError.unsupportedVersion);
    }
    final slot = keyring._password;
    if (slot == null) throw const KeyringException(KeyringError.noSuchSlot);
    final key = await _derive(unorm.nfc(password), slot.salt, params);
    final master = await _open(key, slot.box, keyring.id, 'password');
    return _unlocked(keyring, master);
  }

  /// Opens [keyring] with its backup passphrase.
  Future<UnlockedKeyring> unlockWithPassphrase(
    Keyring keyring,
    String passphrase,
  ) async {
    final slot = keyring._passphrase;
    if (slot == null) throw const KeyringException(KeyringError.noSuchSlot);
    final params = _readablePassphrase(slot.kdf);
    if (params == null) {
      throw const KeyringException(KeyringError.unsupportedVersion);
    }
    final key = await _derive(unorm.nfc(passphrase), slot.salt, params);
    final master = await _open(key, slot.box, keyring.id, 'passphrase');
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

  String _checkedPassword(String password, [PasswordPolicy? rule]) {
    final held = rule ?? policy;
    final problem = held.check(password);
    if (problem != null) {
      throw KeyringException(
        KeyringError.weakPassword,
        passwordProblem: problem,
        minimumLength: held.minimumLength,
      );
    }
    return PasswordPolicy.normalize(password);
  }

  Future<_PasswordSlot> _passwordSlot(
    String normalized,
    List<int> master,
    String keyringId,
  ) async {
    final salt = _randomBytes(16);
    final key = await _derive(normalized, salt);
    return _PasswordSlot(salt, await _seal(key, master, keyringId, 'password'));
  }

  /// Stretches [normalized] with Argon2id on a worker isolate: tens of
  /// megabytes and most of a second of pure-Dart work that would
  /// otherwise freeze the screen while unlocking.
  Future<List<int>> _derive(
    String normalized,
    List<int> salt, [
    PasswordKdf? params,
  ]) {
    final memory = (params ?? kdf).memory;
    final iterations = (params ?? kdf).iterations;
    final secret = utf8.encode(normalized);
    final nonce = List<int>.of(salt);
    return Isolate.run(() async {
      final argon = Argon2id(
        memory: memory,
        iterations: iterations,
        parallelism: 1,
        hashLength: 32,
      );
      final key = await argon.deriveKey(
        secretKey: SecretKey(secret),
        nonce: nonce,
      );
      return key.extractBytes();
    });
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

  /// Sets a new password, held to the codec's [PasswordPolicy]. It opens
  /// this keyring from now on; a copy of the keyring kept before, such as
  /// in an older backup, still opens with the old one ([reset] replaces
  /// the keys themselves).
  Future<UnlockedKeyring> changePassword(String newPassword) async {
    final normalized = _codec._checkedPassword(newPassword);
    final slot = await _codec._passwordSlot(normalized, _master, keyring.id);
    // Set with the codec's parameters now, whatever the old slot used.
    return _next(keyring._copyWith(kdf: _codec.kdf.id, password: slot));
  }

  /// Sets the backup passphrase, held to the codec's
  /// [KeyringCodec.passphrasePolicy] and stretched with its
  /// [KeyringCodec.passphraseKdf]: backups written from now on open with
  /// it as well as with the recovery code.
  Future<UnlockedKeyring> setPassphrase(String passphrase) async {
    final codec = _codec;
    final normalized = codec._checkedPassword(
      passphrase,
      codec.passphrasePolicy,
    );
    final salt = codec._randomBytes(16);
    final key = await codec._derive(normalized, salt, codec.passphraseKdf);
    final box = await codec._seal(key, _master, keyring.id, 'passphrase');
    final slot = _PassphraseSlot(codec.passphraseKdf.id, salt, box);
    return _next(keyring._copyWith(passphrase: () => slot));
  }

  /// Drops the backup passphrase: backups written from now on open with
  /// the recovery code alone.
  UnlockedKeyring removePassphrase() =>
      _next(keyring._copyWith(passphrase: () => null));

  /// Replaces every key: a new master key and database key, the backup
  /// keys of earlier epochs wrapped again under the new master key and a
  /// new epoch for the backups to come, a new recovery code, and
  /// [password] (the one in use, so it is not held to the policy) wrapped
  /// afresh. Devices and the backup passphrase are dropped: they are set
  /// up again. The keyring id stays, as the ledger is the same.
  ///
  /// A copy of the old keyring, as in an older backup, then opens only the
  /// old keys: not this database once it is encrypted again with
  /// [databaseKey], which the caller does (`LedgerVault.resetKeys`).
  Future<ResetKeyring> reset({required String password}) async {
    if (_backupKeys.length >= _maxBackupEpochs) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
    final codec = _codec;
    final id = keyring.id;
    final master = codec._randomBytes(32);
    final database = codec._randomBytes(32);
    final recoveryKey = codec._randomBytes(32);
    final backupKeys = [..._backupKeys, codec._randomBytes(32)];
    final next = Keyring._(
      id: id,
      kdf: codec.kdf.id,
      password: await codec._passwordSlot(
        PasswordPolicy.normalize(password),
        master,
        id,
      ),
      passphrase: null,
      recovery: await codec._seal(recoveryKey, master, id, 'recovery'),
      devices: const [],
      database: await codec._seal(master, database, id, 'database'),
      backupKeys: List.unmodifiable([
        for (var i = 0; i < backupKeys.length; i++)
          await codec._seal(master, backupKeys[i], id, 'backup:${i + 1}'),
      ]),
    );
    return ResetKeyring(
      UnlockedKeyring._(
        codec,
        next,
        master,
        database,
        List.unmodifiable(backupKeys),
      ),
      await encodeRecoveryCode(recoveryKey),
    );
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
    utf8.encode('$_format/$_aadVersion/$keyringId/$purpose');

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
