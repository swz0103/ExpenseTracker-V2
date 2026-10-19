import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'errors.dart';

const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const _prefix = 'ETR1';
const _checksumBytes = 3;

/// Encodes a 32-byte recovery key as `ETR1-XXXX-...` (Crockford base32,
/// 14 groups of 4) with a 24-bit checksum that catches typing mistakes.
Future<String> encodeRecoveryCode(List<int> key) async {
  if (key.length != 32) throw ArgumentError('Recovery key must be 32 bytes.');
  final checksum = (await Sha256().hash(key)).bytes.take(_checksumBytes);
  final bytes = [...key, ...checksum];
  final buffer = StringBuffer();
  var bits = 0;
  var value = 0;
  for (final byte in bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      buffer.write(_alphabet[(value >> bits) & 31]);
    }
    value &= (1 << bits) - 1;
  }
  final text = buffer.toString();
  final groups = [
    for (var i = 0; i < text.length; i += 4) text.substring(i, i + 4),
  ];
  return [_prefix, ...groups].join('-');
}

/// Reads a code typed by a person: case, spaces and dashes are ignored and
/// the look-alike letters O, I and L are read as digits.
Future<Uint8List> decodeRecoveryCode(String code) async {
  var text = code.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (!text.startsWith(_prefix)) {
    throw const KeyringException(KeyringError.invalidFormat);
  }
  text = text
      .substring(_prefix.length)
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');
  if (text.length != 56) {
    throw const KeyringException(KeyringError.invalidFormat);
  }
  final bytes = <int>[];
  var bits = 0;
  var value = 0;
  for (final char in text.split('')) {
    final digit = _alphabet.indexOf(char);
    if (digit < 0) throw const KeyringException(KeyringError.invalidFormat);
    value = (value << 5) | digit;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((value >> bits) & 255);
      value &= (1 << bits) - 1;
    }
  }
  final key = bytes.sublist(0, 32);
  final checksum = (await Sha256().hash(key)).bytes;
  for (var i = 0; i < _checksumBytes; i++) {
    if (bytes[32 + i] != checksum[i]) {
      throw const KeyringException(KeyringError.invalidFormat);
    }
  }
  return Uint8List.fromList(key);
}
