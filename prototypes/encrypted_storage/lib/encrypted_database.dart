import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:sqlite3/sqlite3.dart';

final class StorageKey {
  StorageKey(List<int> bytes) : _bytes = List.unmodifiable(bytes) {
    if (_bytes.length != 32 || _bytes.any((b) => b < 0 || b > 255)) {
      throw ArgumentError('Storage key must contain 32 bytes.');
    }
  }
  factory StorageKey.random() {
    final random = Random.secure();
    return StorageKey(List.generate(32, (_) => random.nextInt(256)));
  }
  final List<int> _bytes;
  String get _hex =>
      _bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  @override
  String toString() => 'StorageKey(redacted)';
}

final class EncryptedStorageUnavailable implements Exception {
  const EncryptedStorageUnavailable();
  @override
  String toString() => 'EncryptedStorageUnavailable';
}

/// Candidate host adapter. Does not persist keys or replace platform secure storage.
ProbeDatabase openEncrypted(
  File file,
  StorageKey key, {
  StorageBinding? storageBinding,
  bool categoryAware = false,
  bool categoryReferences = false,
  bool tagsAware = false,
  bool merchantsAware = false,
  bool transfersAware = false,
  bool fxTransfersAware = false,
  bool refundsAware = false,
  bool reversalsAware = false,
  bool notesAware = false,
  bool correctionsAware = false,
  bool tombstonesAware = false,
  bool budgetsAware = false,
  bool recurringAware = false,
  bool creditCardsAware = false,
  bool cardStatementsAware = false,
  bool cardAuthorizationsAware = false,
  bool installmentsAware = false,
  bool investmentsAware = false,
  bool investmentSalesAware = false,
  bool investmentDividendsAware = false,
  bool investmentSplitsAware = false,
  void Function(String)? migrationCheckpoint,
}) => ProbeDatabase.withExecutor(
  NativeDatabase(file, setup: (raw) => configureEncryption(raw, key)),
  storageBinding: storageBinding,
  categoryAware: categoryAware,
  categoryReferences: categoryReferences,
  tagsAware: tagsAware,
  merchantsAware: merchantsAware,
  transfersAware: transfersAware,
  fxTransfersAware: fxTransfersAware,
  refundsAware: refundsAware,
  reversalsAware: reversalsAware,
  notesAware: notesAware,
  correctionsAware: correctionsAware,
  tombstonesAware: tombstonesAware,
  budgetsAware: budgetsAware,
  recurringAware: recurringAware,
  creditCardsAware: creditCardsAware,
  cardStatementsAware: cardStatementsAware,
  cardAuthorizationsAware: cardAuthorizationsAware,
  installmentsAware: installmentsAware,
  investmentsAware: investmentsAware,
  investmentSalesAware: investmentSalesAware,
  investmentDividendsAware: investmentDividendsAware,
  investmentSplitsAware: investmentSplitsAware,
  migrationCheckpoint: migrationCheckpoint,
);

void configureEncryption(Database raw, StorageKey key) {
  try {
    // Runtime check, not an assert: release builds must never silently use SQLite.
    final version = raw.select('PRAGMA cipher_version');
    if (version.length != 1 ||
        !version.single.values.single.toString().startsWith('4.19.0 ')) {
      throw const EncryptedStorageUnavailable();
    }
    // _hex is exactly 64 hex characters; user text never enters a SQL statement.
    raw.execute('PRAGMA key = "x\'${key._hex}\'"');
    raw.execute('PRAGMA cipher_compatibility = 4');
    raw.execute('PRAGMA cipher_plaintext_header_size = 0');
    raw.execute('PRAGMA temp_store = MEMORY');
    raw.select(
      'SELECT count(*) FROM sqlite_master',
    ); // PRAGMA key alone does not validate a key.
    if (raw.select('PRAGMA cipher_use_hmac').single.values.single.toString() !=
            '1' ||
        raw.select('PRAGMA cipher_page_size').single.values.single.toString() !=
            '4096' ||
        raw
                .select('PRAGMA cipher_plaintext_header_size')
                .single
                .values
                .single
                .toString() !=
            '0') {
      throw const EncryptedStorageUnavailable();
    }
  } catch (_) {
    // Do not expose an underlying exception that might contain a key statement.
    throw const EncryptedStorageUnavailable();
  }
}
