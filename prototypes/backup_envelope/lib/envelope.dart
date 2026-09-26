import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

enum BackupError {
  invalidFormat,
  unsupportedVersion,
  authenticationFailed,
  limitExceeded,
  invalidPassword,
}

final class BackupException implements Exception {
  const BackupException(this.code);
  final BackupError code;
  @override
  String toString() => 'BackupException(${code.name})';
}

final class CreatedBackup {
  const CreatedBackup(this.envelope, this.recoveryKey);
  final String envelope;
  final String recoveryKey;
}

/// Host-only envelope experiment, not the final backup or database format.
final class EnvelopeCodec {
  static const maxPayloadBytes = 16 * 1024 * 1024;
  static const maxEnvelopeCharacters = 24 * 1024 * 1024;
  static const _policy = 'argon2id-v19-m19456-t2-p1-k32';
  static const _prefix = 'ETV2-R1-';
  final _cipher = AesGcm.with256bits();
  final _kdf = Argon2id(
    memory: 19456,
    iterations: 2,
    parallelism: 1,
    hashLength: 32,
  );

  Future<CreatedBackup> create(
    List<int> payload, {
    required String password,
  }) async {
    if (payload.length > maxPayloadBytes)
      throw const BackupException(BackupError.limitExceeded);
    if (payload.any((byte) => byte < 0 || byte > 255))
      throw const BackupException(BackupError.invalidFormat);
    final passwordBytes = _password(password);
    if (password.runes.length < 12)
      throw const BackupException(BackupError.invalidPassword);
    final bytes = List<int>.unmodifiable(payload);
    final dataKey = await _cipher.newSecretKey();
    final recovery = await _cipher.newSecretKey();
    final salt = _random(16);
    final header = <String, Object>{
      'format': 'ExpenseTracker-envelope-probe',
      'version': 1,
      'cipher': 'AES-256-GCM',
      'kdf': _policy,
      'salt': _encode(salt),
      'payloadNonce': _encode(_cipher.newNonce()),
      'passwordNonce': _encode(_cipher.newNonce()),
      'recoveryNonce': _encode(_cipher.newNonce()),
    };
    final wrappingKey = await _kdf.deriveKey(
      secretKey: SecretKey(passwordBytes),
      nonce: salt,
    );
    final dataKeyBytes = await dataKey.extractBytes();
    final passwordBox = await _cipher.encrypt(
      dataKeyBytes,
      secretKey: wrappingKey,
      nonce: _decode(header['passwordNonce'], 12),
      aad: _aad(header, 'password'),
    );
    final recoveryBox = await _cipher.encrypt(
      dataKeyBytes,
      secretKey: recovery,
      nonce: _decode(header['recoveryNonce'], 12),
      aad: _aad(header, 'recovery'),
    );
    final payloadBox = await _cipher.encrypt(
      bytes,
      secretKey: dataKey,
      nonce: _decode(header['payloadNonce'], 12),
      aad: _aad(header, 'payload'),
    );
    final keyBytes = await recovery.extractBytes();
    final checksum = (await Sha256().hash(keyBytes)).bytes.take(4);
    return CreatedBackup(
      jsonEncode({
        'header': header,
        'passwordBox': _boxJson(passwordBox),
        'recoveryBox': _boxJson(recoveryBox),
        'payloadBox': _boxJson(payloadBox),
      }),
      '$_prefix${_encode([...keyBytes, ...checksum])}',
    );
  }

  Future<List<int>> openWithPassword(String envelope, String password) async {
    final parsed = _parse(envelope);
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(_password(password)),
      nonce: _decode(parsed.header['salt'], 16),
    );
    return _open(parsed, key, 'password');
  }

  Future<List<int>> openWithRecovery(
    String envelope,
    String recoveryKey,
  ) async {
    final parsed = _parse(envelope);
    if (!recoveryKey.startsWith(_prefix))
      throw const BackupException(BackupError.invalidFormat);
    final combined = _decode(recoveryKey.substring(_prefix.length), 36);
    final keyBytes = combined.sublist(0, 32);
    final checksum = (await Sha256().hash(keyBytes)).bytes;
    for (var i = 0; i < 4; i++) {
      if (combined[32 + i] != checksum[i])
        throw const BackupException(BackupError.invalidFormat);
    }
    return _open(parsed, SecretKey(keyBytes), 'recovery');
  }

  Future<List<int>> _open(
    _Envelope parsed,
    SecretKey wrappingKey,
    String slot,
  ) async {
    try {
      final wrapped = slot == 'password' ? parsed.password : parsed.recovery;
      final keyBytes = await _cipher.decrypt(
        wrapped,
        secretKey: wrappingKey,
        aad: _aad(parsed.header, slot),
      );
      if (keyBytes.length != 32)
        throw const BackupException(BackupError.invalidFormat);
      return await _cipher.decrypt(
        parsed.payload,
        secretKey: SecretKey(keyBytes),
        aad: _aad(parsed.header, 'payload'),
      );
    } on SecretBoxAuthenticationError {
      throw const BackupException(BackupError.authenticationFailed);
    }
  }

  _Envelope _parse(String envelope) {
    if (envelope.length > maxEnvelopeCharacters)
      throw const BackupException(BackupError.limitExceeded);
    try {
      final root = _map(jsonDecode(envelope), {
        'header',
        'passwordBox',
        'recoveryBox',
        'payloadBox',
      });
      final raw = _map(root['header'], {
        'format',
        'version',
        'cipher',
        'kdf',
        'salt',
        'payloadNonce',
        'passwordNonce',
        'recoveryNonce',
      });
      if (raw['version'] != 1 ||
          raw['format'] != 'ExpenseTracker-envelope-probe' ||
          raw['cipher'] != 'AES-256-GCM' ||
          raw['kdf'] != _policy) {
        throw const BackupException(BackupError.unsupportedVersion);
      }
      // Fixed canonical ordering; never derive resource parameters from untrusted input.
      final header = <String, Object>{
        'format': 'ExpenseTracker-envelope-probe',
        'version': 1,
        'cipher': 'AES-256-GCM',
        'kdf': _policy,
        'salt': _encode(_decode(raw['salt'], 16)),
        'payloadNonce': _encode(_decode(raw['payloadNonce'], 12)),
        'passwordNonce': _encode(_decode(raw['passwordNonce'], 12)),
        'recoveryNonce': _encode(_decode(raw['recoveryNonce'], 12)),
      };
      return _Envelope(
        header,
        _readBox(root['passwordBox'], _decode(header['passwordNonce'], 12), 32),
        _readBox(root['recoveryBox'], _decode(header['recoveryNonce'], 12), 32),
        _readBox(root['payloadBox'], _decode(header['payloadNonce'], 12), null),
      );
    } on FormatException {
      throw const BackupException(BackupError.invalidFormat);
    }
  }
}

final class _Envelope {
  const _Envelope(this.header, this.password, this.recovery, this.payload);
  final Map<String, Object> header;
  final SecretBox password;
  final SecretBox recovery;
  final SecretBox payload;
}

Map<String, dynamic> _map(Object? value, Set<String> expected) {
  if (value is! Map<String, dynamic> ||
      value.length != expected.length ||
      !value.keys.every(expected.contains)) {
    throw const BackupException(BackupError.invalidFormat);
  }
  return value;
}

Map<String, String> _boxJson(SecretBox box) => {
  'cipherText': _encode(box.cipherText),
  'mac': _encode(box.mac.bytes),
};
SecretBox _readBox(Object? value, List<int> nonce, int? expectedLength) {
  final map = _map(value, {'cipherText', 'mac'});
  final data = _decode(map['cipherText'], expectedLength);
  if (data.length > EnvelopeCodec.maxPayloadBytes)
    throw const BackupException(BackupError.limitExceeded);
  return SecretBox(data, nonce: nonce, mac: Mac(_decode(map['mac'], 16)));
}

List<int> _aad(Map<String, Object> header, String purpose) =>
    utf8.encode(jsonEncode([header, purpose]));
List<int> _password(String password) {
  final bytes = utf8.encode(password);
  if (bytes.isEmpty || bytes.length > 1024)
    throw const BackupException(BackupError.invalidPassword);
  return bytes;
}

String _encode(List<int> bytes) => base64UrlEncode(bytes);
List<int> _decode(Object? value, int? length) {
  if (value is! String ||
      value.length > EnvelopeCodec.maxEnvelopeCharacters ||
      (length != null && value.length != ((length + 2) ~/ 3) * 4))
    throw const BackupException(BackupError.invalidFormat);
  try {
    final bytes = base64Url.decode(value);
    if ((length != null && bytes.length != length) || _encode(bytes) != value)
      throw const BackupException(BackupError.invalidFormat);
    return bytes;
  } on FormatException {
    throw const BackupException(BackupError.invalidFormat);
  }
}

List<int> _random(int length) {
  final random = Random.secure();
  return List.generate(length, (_) => random.nextInt(256));
}
