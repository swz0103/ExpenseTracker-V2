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
    return LedgerStore(
      directory,
      SecureKeySlots(vault),
      categoryAware: schema >= 4,
      categoryReferences: schema >= 5,
      tagsAware: schema >= 6,
      merchantsAware: schema >= 7,
      transfersAware: schema >= 8,
      fxTransfersAware: schema >= 9,
      refundsAware: schema >= 10,
      catalogProtection: CatalogProtection(
        identity,
        (exists) => access.load(databaseExists: () async => exists),
      ),
    );
  });
}

abstract interface class BackupDocuments {
  Future<bool> save(String encrypted);
  Future<String?> open();
}

final class AndroidBackupDocuments implements BackupDocuments {
  static const channel = MethodChannel('expense_preview/documents');
  @override
  Future<bool> save(String encrypted) async =>
      await channel.invokeMethod<bool>('save', encrypted) ?? false;
  @override
  Future<String?> open() => channel.invokeMethod<String>('open');
}
