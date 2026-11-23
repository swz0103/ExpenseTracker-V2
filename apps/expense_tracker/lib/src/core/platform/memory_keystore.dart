import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:vault/backup_security.dart';

/// A stand-in for the phone's Keystore off Android (tests, the desktop
/// build): what it wraps stays in this process's memory, and the blob it
/// hands back is a random handle, never the secret. A blob opens only for
/// the context it was wrapped with, as the real key requires, and only
/// in the run that made it: after a restart, a ledger opened without a
/// password needs its recovery code.
final class MemoryKeystore implements DeviceKeyWrapper {
  MemoryKeystore._();

  /// The one key of this process, as a phone has one Keystore.
  static final instance = MemoryKeystore._();

  final _kept = <String, (Uint8List, Uint8List)>{};
  final _random = Random.secure();

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) async {
    final handle = base64Url.encode([
      for (var i = 0; i < 24; i++) _random.nextInt(256),
    ]);
    _kept[handle] = (Uint8List.fromList(secret), Uint8List.fromList(context));
    return utf8.encode('memory:$handle');
  }

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) async {
    final text = utf8.decode(wrapped, allowMalformed: true);
    final kept = text.startsWith('memory:') ? _kept[text.substring(7)] : null;
    if (kept == null || !listEquals(kept.$2, context)) {
      throw StateError('Not wrapped by this run.');
    }
    return Uint8List.fromList(kept.$1);
  }
}
