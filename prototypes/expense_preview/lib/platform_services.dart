import 'dart:io';

import 'package:android_foundation/key_access.dart';
import 'package:android_foundation/secure_key_slots.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:storage_generation_probe/catalog_protection.dart';

import 'preview_engine.dart';
import 'app_pin.dart';

final class AndroidPreviewVault implements PreviewVault, SlotVault {
  static const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'expense_v2_preview_v1',
      resetOnError: false,
      migrateOnAlgorithmChange: false,
    ),
  );
  @override
  Future<String?> read(String name) => storage.read(key: name);
  @override
  Future<void> write(String name, String value) =>
      storage.write(key: name, value: value);
}

/// Optional local convenience unlock. The master password remains portable only
/// through the encrypted backup; this copy is bound to the Android Keystore.
abstract interface class DeviceUnlockStore {
  Future<bool> isEnabled();
  Future<void> enable(String password);
  Future<String?> readPassword();
  Future<void> disable();
}

final class AndroidDeviceUnlockStore implements DeviceUnlockStore {
  static const _marker = 'device_unlock_enabled_v1';
  static const _secret = 'master_password_v1';
  static const _protected = FlutterSecureStorage(
    aOptions: AndroidOptions.biometric(
      storageNamespace: 'expense_v2_device_unlock_v1',
      enforceBiometrics: true,
      requireBiometricsPerOperation: true,
      resetOnError: false,
      migrateOnAlgorithmChange: false,
      biometricPromptTitle: '解鎖記帳 V2',
    ),
  );

  final AndroidPreviewVault _metadata = AndroidPreviewVault();

  @override
  Future<bool> isEnabled() async => await _metadata.read(_marker) == '1';

  @override
  Future<void> enable(String password) async {
    if (password.isEmpty) throw ArgumentError.value(password, 'password');
    // Publish the marker only after a Keystore-authenticated write succeeds.
    await _protected.write(key: _secret, value: password);
    await _metadata.write(_marker, '1');
  }

  @override
  Future<String?> readPassword() async {
    if (!await isEnabled()) return null;
    return _protected.read(key: _secret);
  }

  @override
  Future<void> disable() async {
    // Hide the shortcut before any protected-store operation can fail.
    await _metadata.write(_marker, '0');
    await _protected.delete(key: _secret);
  }
}

final class AndroidPinRecordStore implements PinRecordStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'expense_v2_app_pin_v1',
      resetOnError: false,
      migrateOnAlgorithmChange: false,
    ),
  );
  static const _key = 'app_pin_verifier_v1';

  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> delete() => _storage.delete(key: _key);
}

final class _CatalogVault implements KeyVault {
  _CatalogVault(this.vault, this.identity);
  final PreviewVault vault;
  final PublicId identity;
  @override
  Future<String?> read() => vault.read('catalog_${identity.value}');
  @override
  Future<void> write(String value) =>
      vault.write('catalog_${identity.value}', value);
}

Future<PreviewEngine> createEngine() async {
  final root = await getApplicationSupportDirectory();
  final vault = AndroidPreviewVault();
  return PreviewEngine(Directory('${root.path}/preview-v1'), vault, (
    directory,
    identity,
    schema,
  ) {
    final access = KeyAccess(_CatalogVault(vault, identity));
    final capabilities = PreviewCapabilities(schema);
    return LedgerStore(
      directory,
      SecureKeySlots(vault),
      categoryAware: capabilities.categories,
      categoryReferences: capabilities.categoryReferences,
      tagsAware: capabilities.tags,
      merchantsAware: capabilities.merchants,
      transfersAware: capabilities.transfers,
      fxTransfersAware: capabilities.crossCurrencyTransfers,
      refundsAware: capabilities.refunds,
      reversalsAware: capabilities.reversals,
      notesAware: capabilities.notes,
      correctionsAware: capabilities.corrections,
      tombstonesAware: capabilities.tombstones,
      budgetsAware: capabilities.budgets,
      recurringAware: capabilities.recurring,
      catalogProtection: CatalogProtection(
        identity,
        (exists) => access.load(databaseExists: () async => exists),
      ),
    );
  }, schemaVersion: currentPreviewSchemaVersion);
}

abstract interface class BackupDocuments {
  Future<bool> save(String encrypted);
  Future<String?> open();
  Future<bool> chooseSimpleImport();
  Future<String?> readSimpleImport();
  Future<void> discardSimpleImport();
  Future<bool> chooseSimpleExport(String format);
  Future<bool> writeSimpleExport(String contents);
  Future<void> discardSimpleExport();
}

final class AndroidBackupDocuments implements BackupDocuments {
  static const channel = MethodChannel('expense_preview/documents');
  @override
  Future<bool> save(String encrypted) async =>
      await channel.invokeMethod<bool>('save', encrypted) ?? false;
  @override
  Future<String?> open() => channel.invokeMethod<String>('open');

  @override
  Future<bool> chooseSimpleImport() async =>
      await channel.invokeMethod<bool>('chooseSimpleImport') ?? false;
  @override
  Future<String?> readSimpleImport() =>
      channel.invokeMethod<String>('readSimpleImport');
  @override
  Future<void> discardSimpleImport() =>
      channel.invokeMethod<void>('discardSimpleImport');

  @override
  Future<bool> chooseSimpleExport(String format) async =>
      await channel.invokeMethod<bool>('chooseSimpleExport', format) ?? false;
  @override
  Future<bool> writeSimpleExport(String contents) async =>
      await channel.invokeMethod<bool>('writeSimpleExport', contents) ?? false;
  @override
  Future<void> discardSimpleExport() =>
      channel.invokeMethod<void>('discardSimpleExport');
}
