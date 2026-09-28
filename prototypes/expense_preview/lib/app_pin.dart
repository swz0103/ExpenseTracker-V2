import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

final class AppPinRejected implements Exception {
  const AppPinRejected();
}

/// Device-only second factor for the Keystore-authenticated unlock shortcut.
/// A PIN never encrypts or replaces the ledger password or recovery text.
abstract interface class AppPinStore {
  Future<bool> isEnabled();
  Future<void> enable(String pin);
  Future<bool> matches(String pin);
  Future<void> disable();
}

abstract interface class PinRecordStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

final class VerifiedAppPinStore implements AppPinStore {
  VerifiedAppPinStore(this._record);

  final PinRecordStore _record;
  static const _iterations = 210000;
  static const _maxFailures = 5;
  static final _digits = RegExp(r'^[0-9]{6,12}$');
  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  @override
  Future<bool> isEnabled() async => await _record.read() != null;

  @override
  Future<void> enable(String pin) async {
    if (!_digits.hasMatch(pin)) throw const FormatException('App PIN format');
    if (await isEnabled()) throw StateError('App PIN already enabled');
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = await _derive(pin, salt);
    await _record.write(
      jsonEncode({
        'version': 1,
        'iterations': _iterations,
        'salt': base64Encode(salt),
        'hash': base64Encode(hash),
        'failures': 0,
      }),
    );
  }

  @override
  Future<bool> matches(String pin) async {
    final saved = await _record.read();
    if (saved == null) return false;
    try {
      final data = jsonDecode(saved);
      if (data is! Map<String, dynamic> ||
          data.length != 5 ||
          data['version'] != 1 ||
          data['iterations'] != _iterations ||
          data['salt'] is! String ||
          data['hash'] is! String ||
          data['failures'] is! int) {
        return false;
      }
      final failures = data['failures'] as int;
      if (failures < 0 || failures >= _maxFailures) return false;
      final salt = base64Decode(data['salt'] as String);
      final expected = base64Decode(data['hash'] as String);
      if (salt.length != 16 || expected.length != 32) return false;
      var equal = false;
      if (_digits.hasMatch(pin)) {
        final actual = await _derive(pin, salt);
        var difference = 0;
        for (var i = 0; i < expected.length; i++) {
          difference |= expected[i] ^ actual[i];
        }
        equal = difference == 0;
      }
      if (!equal) {
        data['failures'] = failures + 1;
        await _record.write(jsonEncode(data));
        return false;
      }
      if (failures > 0) {
        data['failures'] = 0;
        await _record.write(jsonEncode(data));
      }
      return true;
    } on FormatException {
      return false;
    }
  }

  @override
  Future<void> disable() => _record.delete();

  Future<List<int>> _derive(String pin, List<int> salt) async =>
      (await _pbkdf2.deriveKeyFromPassword(
        password: pin,
        nonce: salt,
      )).extractBytes();
}
