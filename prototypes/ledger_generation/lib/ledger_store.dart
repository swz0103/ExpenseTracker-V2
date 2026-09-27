import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:storage_generation_probe/key_slots.dart';
import 'package:storage_generation_probe/lock_wait.dart';
import 'package:storage_generation_probe/catalog_protection.dart';
import 'package:validated_restore_probe/snapshot.dart';

StorageBinding _binding(GenerationReceipt receipt) => StorageBinding(
  receipt.generation,
  receipt.slot,
  receipt.operation,
  receipt.fingerprint,
);

final class LedgerPayload implements GenerationPayload {
  final codec = SnapshotCodec(generationAware: true);
  @override
  int get maxBytes => EnvelopeCodec.maxPayloadBytes;
  @override
  String canonicalize(String input) =>
      utf8.decode(codec.canonicalize(utf8.encode(input)));
  @override
  Future<void> create(
    File file,
    StorageKey key,
    GenerationReceipt receipt,
    String input,
    void Function(String)? checkpoint,
  ) => codec.stage(
    utf8.encode(input),
    file,
    checkpoint: checkpoint,
    openDatabase: (target) =>
        openEncrypted(target, key, storageBinding: _binding(receipt)),
  );

  @override
  Future<String> inspect(
    File file,
    StorageKey key,
    GenerationReceipt receipt,
  ) async {
    // Refuse migration during inspection: only explicitly staged v3 is accepted.
    final raw = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      configureEncryption(raw, key);
      if (raw.userVersion != 3 ||
          raw.select('PRAGMA cipher_integrity_check').isNotEmpty ||
          raw
              .select(
                "SELECT name FROM sqlite_master WHERE type IN ('view','trigger')",
              )
              .isNotEmpty) {
        throw StateError('Unexpected Ledger generation');
      }
    } finally {
      raw.close();
    }
    final db = openEncrypted(file, key, storageBinding: _binding(receipt));
    try {
      // Installation fingerprint authenticates the imported input, not the live
      // ledger after later ACID postings. Capture validates its current contents.
      return utf8.decode(await codec.capture(db));
    } finally {
      await db.close();
    }
  }
}

/// Host integration probe. All financial operations share the lifecycle lock,
/// and every database connection closes before that lock is released.
final class LedgerStore {
  LedgerStore(
    Directory directory,
    KeySlots keys, {
    CatalogProtection? catalogProtection,
    Duration lockTimeout = const Duration(seconds: 10),
  }) : generations = GenerationStore(
         directory,
         keys,
         payload: LedgerPayload(),
         catalogProtection: catalogProtection,
         lockTimeout: lockTimeout,
       );
  final GenerationStore generations;

  Future<GenerationReceipt> restore(
    String envelope,
    OperationId operation, {
    String? password,
    String? recoveryKey,
    void Function(String)? checkpoint,
    LockWaitCancellation? cancellation,
  }) async {
    if ((password == null) == (recoveryKey == null))
      throw ArgumentError('One unlock method required');
    final codec = EnvelopeCodec();
    final bytes = password != null
        ? await codec.openWithPassword(envelope, password)
        : await codec.openWithRecovery(envelope, recoveryKey!);
    return generations.install(
      utf8.decode(bytes),
      operation,
      checkpoint: checkpoint,
      cancellation: cancellation,
    );
  }

  Future<List<int>> snapshot({LockWaitCancellation? cancellation}) async {
    final current = await generations.current(cancellation: cancellation);
    if (current == null) throw StateError('No Ledger generation');
    return utf8.encode(current.value);
  }

  Future<CreatedBackup> backup(
    String password, {
    LockWaitCancellation? cancellation,
  }) async => EnvelopeCodec().create(
    await snapshot(cancellation: cancellation),
    password: password,
  );

  Future<T> _use<T>(
    Future<T> Function(ProbeDatabase) work, {
    LockWaitCancellation? cancellation,
  }) => generations.withCurrent((file, key, receipt) async {
    final db = openEncrypted(file, key, storageBinding: _binding(receipt));
    try {
      return await work(db);
    } finally {
      await db.close();
    }
  }, cancellation: cancellation);

  Future<CommitResult> post(
    Posting posting, {
    LockWaitCancellation? cancellation,
  }) => _use(
    (db) => FinancialWorkflows(db).post(posting),
    cancellation: cancellation,
  );
  Future<Money> balance(
    PostingAccount account, {
    LockWaitCancellation? cancellation,
  }) => _use(
    (db) => FinancialWorkflows(db).ledger.balance(account),
    cancellation: cancellation,
  );
}
