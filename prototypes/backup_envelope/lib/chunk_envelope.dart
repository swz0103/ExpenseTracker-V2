import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'envelope.dart';

final class CreatedChunkSession {
  const CreatedChunkSession({
    required this.metadata,
    required this.recoveryKey,
    required this.session,
  });

  final String metadata;
  final String recoveryKey;
  final ChunkEnvelopeSession session;
}

/// One authenticated data-key session for a manifest and all of its chunks.
/// Password KDF work happens once per open, not once per chunk.
final class ChunkEnvelopeCodec {
  static const maxChunkBytes = 2 * 1024 * 1024;
  static const maxEnvelopeCharacters = 3 * 1024 * 1024;
  static const _policy = 'argon2id-v19-m19456-t2-p1-k32';
  static const _prefix = 'ETV2-R2-';

  final _cipher = AesGcm.with256bits();
  final _kdf = Argon2id(
    memory: 19456,
    iterations: 2,
    parallelism: 1,
    hashLength: 32,
  );

  Future<CreatedChunkSession> create({
    required String password,
    String? recoveryKey,
  }) async {
    final passwordBytes = _chunkPassword(password);
    if (password.runes.length < 12) {
      throw const BackupException(BackupError.invalidPassword);
    }
    final recovery = recoveryKey == null
        ? await _cipher.newSecretKey()
        : await _readRecoveryKey(recoveryKey);
    final dataKey = await _cipher.newSecretKey();
    final salt = _chunkRandom(16);
    final header = <String, Object>{
      'format': 'ExpenseTracker-chunk-key-probe',
      'version': 1,
      'cipher': 'AES-256-GCM',
      'kdf': _policy,
      'salt': _chunkEncode(salt),
      'passwordNonce': _chunkEncode(_cipher.newNonce()),
      'recoveryNonce': _chunkEncode(_cipher.newNonce()),
      'sessionId': _chunkEncode(_chunkRandom(16)),
    };
    final wrappingKey = await _kdf.deriveKey(
      secretKey: SecretKey(passwordBytes),
      nonce: salt,
    );
    final keyBytes = await dataKey.extractBytes();
    final passwordBox = await _cipher.encrypt(
      keyBytes,
      secretKey: wrappingKey,
      nonce: _chunkDecode(header['passwordNonce'], 12),
      aad: _chunkAad(header, 'password'),
    );
    final recoveryBox = await _cipher.encrypt(
      keyBytes,
      secretKey: recovery,
      nonce: _chunkDecode(header['recoveryNonce'], 12),
      aad: _chunkAad(header, 'recovery'),
    );
    final recoveryBytes = await recovery.extractBytes();
    final checksum = (await Sha256().hash(recoveryBytes)).bytes.take(4);
    return CreatedChunkSession(
      metadata: jsonEncode({
        'header': header,
        'passwordBox': _chunkBoxJson(passwordBox),
        'recoveryBox': _chunkBoxJson(recoveryBox),
      }),
      recoveryKey: '$_prefix${_chunkEncode([...recoveryBytes, ...checksum])}',
      session: ChunkEnvelopeSession._(header, dataKey),
    );
  }

  Future<ChunkEnvelopeSession> openWithPassword(
    String metadata,
    String password,
  ) async {
    final parsed = _parse(metadata);
    final key = await _kdf.deriveKey(
      secretKey: SecretKey(_chunkPassword(password)),
      nonce: _chunkDecode(parsed.header['salt'], 16),
    );
    return _open(parsed, key, 'password');
  }

  Future<ChunkEnvelopeSession> openWithRecovery(
    String metadata,
    String recoveryKey,
  ) async =>
      _open(_parse(metadata), await _readRecoveryKey(recoveryKey), 'recovery');

  Future<ChunkEnvelopeSession> _open(
    _ChunkKeyMetadata parsed,
    SecretKey wrappingKey,
    String slot,
  ) async {
    try {
      final wrapped = slot == 'password' ? parsed.password : parsed.recovery;
      final keyBytes = await _cipher.decrypt(
        wrapped,
        secretKey: wrappingKey,
        aad: _chunkAad(parsed.header, slot),
      );
      if (keyBytes.length != 32) {
        throw const BackupException(BackupError.invalidFormat);
      }
      return ChunkEnvelopeSession._(parsed.header, SecretKey(keyBytes));
    } on SecretBoxAuthenticationError {
      throw const BackupException(BackupError.authenticationFailed);
    }
  }

  Future<SecretKey> _readRecoveryKey(String recoveryKey) async {
    if (!recoveryKey.startsWith(_prefix)) {
      throw const BackupException(BackupError.invalidFormat);
    }
    final combined = _chunkDecode(recoveryKey.substring(_prefix.length), 36);
    final keyBytes = combined.sublist(0, 32);
    final checksum = (await Sha256().hash(keyBytes)).bytes;
    for (var index = 0; index < 4; index++) {
      if (combined[32 + index] != checksum[index]) {
        throw const BackupException(BackupError.invalidFormat);
      }
    }
    return SecretKey(keyBytes);
  }

  _ChunkKeyMetadata _parse(String metadata) {
    if (metadata.length > 16384) {
      throw const BackupException(BackupError.limitExceeded);
    }
    try {
      final root = _chunkMap(jsonDecode(metadata), {
        'header',
        'passwordBox',
        'recoveryBox',
      });
      final raw = _chunkMap(root['header'], {
        'format',
        'version',
        'cipher',
        'kdf',
        'salt',
        'passwordNonce',
        'recoveryNonce',
        'sessionId',
      });
      if (raw['format'] != 'ExpenseTracker-chunk-key-probe' ||
          raw['version'] != 1 ||
          raw['cipher'] != 'AES-256-GCM' ||
          raw['kdf'] != _policy) {
        throw const BackupException(BackupError.unsupportedVersion);
      }
      final header = <String, Object>{
        'format': 'ExpenseTracker-chunk-key-probe',
        'version': 1,
        'cipher': 'AES-256-GCM',
        'kdf': _policy,
        'salt': _chunkEncode(_chunkDecode(raw['salt'], 16)),
        'passwordNonce': _chunkEncode(_chunkDecode(raw['passwordNonce'], 12)),
        'recoveryNonce': _chunkEncode(_chunkDecode(raw['recoveryNonce'], 12)),
        'sessionId': _chunkEncode(_chunkDecode(raw['sessionId'], 16)),
      };
      return _ChunkKeyMetadata(
        header,
        _chunkReadBox(
          root['passwordBox'],
          _chunkDecode(header['passwordNonce'], 12),
          32,
        ),
        _chunkReadBox(
          root['recoveryBox'],
          _chunkDecode(header['recoveryNonce'], 12),
          32,
        ),
      );
    } on FormatException {
      throw const BackupException(BackupError.invalidFormat);
    }
  }
}

final class ChunkEnvelopeSession {
  ChunkEnvelopeSession._(this._header, this._dataKey);

  final Map<String, Object> _header;
  final SecretKey _dataKey;
  final _cipher = AesGcm.with256bits();

  Future<String> seal(List<int> bytes, {required String purpose}) async {
    _validatePurpose(purpose);
    if (bytes.length > ChunkEnvelopeCodec.maxChunkBytes ||
        bytes.any((byte) => byte < 0 || byte > 255)) {
      throw const BackupException(BackupError.limitExceeded);
    }
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      List<int>.unmodifiable(bytes),
      secretKey: _dataKey,
      nonce: nonce,
      aad: _chunkAad(_header, purpose),
    );
    return jsonEncode({'nonce': _chunkEncode(nonce), ..._chunkBoxJson(box)});
  }

  Future<List<int>> open(String envelope, {required String purpose}) async {
    _validatePurpose(purpose);
    if (envelope.length > ChunkEnvelopeCodec.maxEnvelopeCharacters) {
      throw const BackupException(BackupError.limitExceeded);
    }
    try {
      final raw = _chunkMap(jsonDecode(envelope), {
        'nonce',
        'cipherText',
        'mac',
      });
      final nonce = _chunkDecode(raw['nonce'], 12);
      final box = _chunkReadBox(raw, nonce, null);
      if (box.cipherText.length > ChunkEnvelopeCodec.maxChunkBytes) {
        throw const BackupException(BackupError.limitExceeded);
      }
      return await _cipher.decrypt(
        box,
        secretKey: _dataKey,
        aad: _chunkAad(_header, purpose),
      );
    } on SecretBoxAuthenticationError {
      throw const BackupException(BackupError.authenticationFailed);
    } on FormatException {
      throw const BackupException(BackupError.invalidFormat);
    }
  }
}

final class _ChunkKeyMetadata {
  const _ChunkKeyMetadata(this.header, this.password, this.recovery);

  final Map<String, Object> header;
  final SecretBox password;
  final SecretBox recovery;
}

void _validatePurpose(String purpose) {
  if (!RegExp(r'^(manifest|chunk-[0-9]{8})$').hasMatch(purpose)) {
    throw const BackupException(BackupError.invalidFormat);
  }
}

Map<String, dynamic> _chunkMap(Object? value, Set<String> expected) {
  if (value is! Map<String, dynamic> ||
      value.length != expected.length ||
      !value.keys.every(expected.contains)) {
    throw const BackupException(BackupError.invalidFormat);
  }
  return value;
}

Map<String, String> _chunkBoxJson(SecretBox box) => {
  'cipherText': _chunkEncode(box.cipherText),
  'mac': _chunkEncode(box.mac.bytes),
};

SecretBox _chunkReadBox(Object? value, List<int> nonce, int? length) {
  final map = value is Map<String, dynamic> && value.containsKey('nonce')
      ? value
      : _chunkMap(value, {'cipherText', 'mac'});
  final cipherText = _chunkDecode(map['cipherText'], length);
  return SecretBox(
    cipherText,
    nonce: nonce,
    mac: Mac(_chunkDecode(map['mac'], 16)),
  );
}

List<int> _chunkAad(Map<String, Object> header, String purpose) =>
    utf8.encode(jsonEncode([header, purpose]));

List<int> _chunkPassword(String password) {
  final bytes = utf8.encode(password);
  if (bytes.isEmpty || bytes.length > 1024) {
    throw const BackupException(BackupError.invalidPassword);
  }
  return bytes;
}

String _chunkEncode(List<int> bytes) => base64UrlEncode(bytes);

List<int> _chunkDecode(Object? value, int? length) {
  if (value is! String ||
      value.length > ChunkEnvelopeCodec.maxEnvelopeCharacters ||
      (length != null && value.length != ((length + 2) ~/ 3) * 4)) {
    throw const BackupException(BackupError.invalidFormat);
  }
  try {
    final bytes = base64Url.decode(value);
    if ((length != null && bytes.length != length) ||
        _chunkEncode(bytes) != value) {
      throw const BackupException(BackupError.invalidFormat);
    }
    return bytes;
  } on FormatException {
    throw const BackupException(BackupError.invalidFormat);
  }
}

List<int> _chunkRandom(int length) {
  final random = Random.secure();
  return List.generate(length, (_) => random.nextInt(256));
}
