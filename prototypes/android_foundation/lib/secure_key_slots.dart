import 'dart:convert';
import 'dart:math';

import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:storage_generation_probe/key_slots.dart';

import 'key_access.dart';

abstract interface class SlotVault {
  Future<String?> read(String slot);
  Future<void> write(String slot, String value);
}

/// Candidate adapter. The lifecycle coordinator serializes writers across
/// processes; this guard only protects overlapping creates in one isolate.
final class SecureKeySlots implements KeySlots {
  SecureKeySlots(this.vault);
  final SlotVault vault;
  static final _creating = <String>{};

  @override
  Future<void> create(PublicId slot) async {
    final name = slot.value;
    if (!_creating.add(name)) throw const KeyUnavailable();
    try {
      if (await vault.read(name) != null) throw const KeyUnavailable();
      final random = Random.secure();
      final value =
          'v1:${base64Encode(List.generate(32, (_) => random.nextInt(256)))}';
      await vault.write(name, value);
      if (await vault.read(name) != value) throw const KeyUnavailable();
    } catch (_) {
      // Never overwrite, delete or reset a slot after an ambiguous write.
      throw const KeyUnavailable();
    } finally {
      _creating.remove(name);
    }
  }

  @override
  Future<StorageKey> read(PublicId slot) async {
    try {
      final value = await vault.read(slot.value);
      if (value == null || value.length != 47 || !value.startsWith('v1:')) {
        throw const KeyUnavailable();
      }
      final bytes = base64Decode(value.substring(3));
      if (bytes.length != 32 || 'v1:${base64Encode(bytes)}' != value) {
        throw const KeyUnavailable();
      }
      return StorageKey(bytes);
    } catch (_) {
      throw const KeyUnavailable();
    }
  }
}
