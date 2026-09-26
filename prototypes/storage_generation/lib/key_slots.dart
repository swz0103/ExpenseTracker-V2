import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';

/// Create never replaces an existing slot; read never creates or resets one.
abstract interface class KeySlots {
  Future<void> create(PublicId slot);
  Future<StorageKey> read(PublicId slot);
}
