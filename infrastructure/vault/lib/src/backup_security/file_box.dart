import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'keyring.dart';

/// Seals files kept beside the ledger, such as receipt photos, with
/// AES-256-GCM under a key derived (HKDF-SHA256) from the database key
/// and a purpose. The database key never changes and a restored backup
/// brings it back, so sealed files open again after a restore.
///
/// A sealed file: the 6-byte magic, the 12-byte nonce, the ciphertext and
/// the 16-byte tag; the magic and the file's [name] are bound in as
/// associated data, so a file cannot be swapped for another one.
final class FileBox {
  FileBox._(this._key);

  static final _magic = ascii.encode('ETFB1\n');
  static final _cipher = AesGcm.with256bits();

  final SecretKey _key;

  /// The box for files of [purpose], such as `receipts`.
  static Future<FileBox> derive(UnlockedKeyring keys, String purpose) async {
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(keys.databaseKey),
      nonce: utf8.encode('ExpenseTracker file box'),
      info: utf8.encode(purpose),
    );
    return FileBox._(key);
  }

  List<int> _aad(String name) => [..._magic, ...utf8.encode(name)];

  Future<Uint8List> seal(String name, List<int> plain) async {
    final box = await _cipher.encrypt(
      plain,
      secretKey: _key,
      aad: _aad(name),
    );
    return Uint8List.fromList([
      ..._magic,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// The plain bytes; throws [SecretBoxAuthenticationError] when [sealed]
  /// was changed or belongs to another name or ledger.
  Future<Uint8List> open(String name, List<int> sealed) async {
    if (sealed.length < _magic.length + 28) {
      throw const FormatException('Not a sealed file.');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (sealed[i] != _magic[i]) {
        throw const FormatException('Not a sealed file.');
      }
    }
    final body = sealed.sublist(_magic.length);
    final plain = await _cipher.decrypt(
      SecretBox(
        body.sublist(12, body.length - 16),
        nonce: body.sublist(0, 12),
        mac: Mac(body.sublist(body.length - 16)),
      ),
      secretKey: _key,
      aad: _aad(name),
    );
    return Uint8List.fromList(plain);
  }
}
