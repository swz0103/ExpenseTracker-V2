import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_access.dart';

final class AndroidKeyVault implements KeyVault {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'expense_v2_foundation_v1',
      resetOnError: false,
      migrateOnAlgorithmChange: false,
    ),
  );
  static const _name = 'fixture_database_key_v1';
  @override
  Future<String?> read() => _storage.read(key: _name);
  @override
  Future<void> write(String value) => _storage.write(key: _name, value: value);
}
