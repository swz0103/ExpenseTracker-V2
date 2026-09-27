import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';

/// Composition supplies a stable local store identity and its dedicated key.
/// Called only under the lifecycle lock. A missing key for an existing catalog
/// must fail; a retained key for interrupted initialization must be reused.
final class CatalogProtection {
  CatalogProtection(this.identity, this.loadKey);
  final PublicId identity;
  final Future<StorageKey> Function(bool catalogExists) loadKey;
}
