import 'dart:convert';
import 'dart:math';

import 'package:encrypted_storage_probe/encrypted_database.dart';

abstract interface class KeyVault {
  Future<String?> read();
  Future<void> write(String value);
}

final class KeyUnavailable implements Exception {
  const KeyUnavailable();
  @override
  String toString() => 'KeyUnavailable';
}

/// Prototype key lifecycle. Never regenerates a key for an existing database.
final class KeyAccess {
  KeyAccess(this.vault);
  final KeyVault vault;
  Future<StorageKey>? _loading;
  Future<StorageKey> load({required Future<bool> Function() databaseExists}) =>
      _loading ??= _load(databaseExists).whenComplete(() => _loading = null);

  Future<StorageKey> _load(Future<bool> Function() exists) async {
    try {
      final saved = await vault.read();
      if (saved != null) return _decode(saved);
      if (await exists()) throw const KeyUnavailable();
      final random = Random.secure();
      final encoded =
          'v1:${base64Encode(List.generate(32, (_) => random.nextInt(256)))}';
      await vault.write(encoded);
      if (await vault.read() != encoded) throw const KeyUnavailable();
      return _decode(encoded);
    } catch (_) {
      // Never reset storage or expose a key-bearing underlying exception.
      throw const KeyUnavailable();
    }
  }

  StorageKey _decode(String value) {
    if (!value.startsWith('v1:') || value.length != 47) {
      throw const KeyUnavailable();
    }
    final bytes = base64Decode(value.substring(3));
    if (bytes.length != 32 || 'v1:${base64Encode(bytes)}' != value) {
      throw const KeyUnavailable();
    }
    return StorageKey(bytes);
  }
}
