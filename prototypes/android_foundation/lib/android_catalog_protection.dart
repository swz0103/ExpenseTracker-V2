import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:storage_generation_probe/catalog_protection.dart';

import 'key_access.dart';

/// Identity comes from the owning composition, never an imported backup.
CatalogProtection androidCatalogProtection(PublicId identity) {
  final access = KeyAccess(_CatalogVault(identity));
  return CatalogProtection(
    identity,
    (exists) => access.load(databaseExists: () async => exists),
  );
}

final class _CatalogVault implements KeyVault {
  _CatalogVault(this.identity);
  final PublicId identity;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'expense_v2_control_probe_v1',
      resetOnError: false,
      migrateOnAlgorithmChange: false,
    ),
  );
  String get _name => 'catalog_v1_${identity.value}';
  @override
  Future<String?> read() => _storage.read(key: _name);
  @override
  Future<void> write(String value) => _storage.write(key: _name, value: value);
}
