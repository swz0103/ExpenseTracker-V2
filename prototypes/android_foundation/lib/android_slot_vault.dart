import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_key_slots.dart';

final class AndroidSlotVault implements SlotVault {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'expense_v2_generation_probe_v1',
      resetOnError: false,
      migrateOnAlgorithmChange: false,
    ),
  );
  @override
  Future<String?> read(String slot) => _storage.read(key: 'slot_v1_$slot');
  @override
  Future<void> write(String slot, String value) =>
      _storage.write(key: 'slot_v1_$slot', value: value);
}
