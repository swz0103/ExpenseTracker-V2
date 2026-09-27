import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:accounts/accounts.dart';
import 'package:categories/categories.dart';
import 'package:tags/tags.dart';
import 'package:merchants/merchants.dart';
import 'package:drift/drift.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/adapters.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';
import 'package:modular_persistence_probe/tags_adapter.dart';
import 'package:modular_persistence_probe/merchants_adapter.dart';
import 'package:modular_persistence_probe/tagged_posting.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:storage_generation_probe/key_slots.dart';
import 'package:storage_generation_probe/lock_wait.dart';
import 'package:storage_generation_probe/catalog_protection.dart';
import 'package:validated_restore_probe/snapshot.dart';

part 'ledger_session.dart';
part 'category_session.dart';
part 'tag_session.dart';
part 'tag_references.dart';
part 'merchant_session.dart';
part 'merchant_references.dart';
part 'allocation_session.dart';
part 'session_capacity.dart';

StorageBinding _binding(GenerationReceipt receipt) => StorageBinding(
  receipt.generation,
  receipt.slot,
  receipt.operation,
  receipt.fingerprint,
);

final class LedgerPayload implements GenerationPayload {
  LedgerPayload({
    bool categoryAware = false,
    bool categoryReferences = false,
    bool tagsAware = false,
    this.merchantsAware = false,
  }) : tagsAware = tagsAware || merchantsAware,
       categoryReferences = categoryReferences || tagsAware || merchantsAware,
       categoryAware =
           categoryAware || categoryReferences || tagsAware || merchantsAware,
       codec = SnapshotCodec(
         generationAware: true,
         categoryAware: categoryAware,
         categoryReferences: categoryReferences,
         tagsAware: tagsAware,
         merchantsAware: merchantsAware,
       );
  final bool categoryAware;
  final bool categoryReferences;
  final bool tagsAware;
  final bool merchantsAware;
  final SnapshotCodec codec;
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
    openDatabase: (target) => openEncrypted(
      target,
      key,
      storageBinding: _binding(receipt),
      categoryAware: categoryAware,
      categoryReferences: categoryReferences,
      tagsAware: tagsAware,
      merchantsAware: merchantsAware,
    ),
  );

  @override
  Future<String> inspect(
    File file,
    StorageKey key,
    GenerationReceipt receipt,
  ) async {
    // Inspect the physical version first; never migrate while opening a source.
    final raw = sqlite3.open(file.path, mode: OpenMode.readOnly);
    late int version;
    try {
      configureEncryption(raw, key);
      version = raw.userVersion;
      if (!(version == 3 ||
              (categoryAware && version == 4) ||
              (categoryReferences && version == 5) ||
              (tagsAware && version == 6) ||
              (merchantsAware && version == 7)) ||
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
    final sourceCodec = SnapshotCodec(
      generationAware: true,
      categoryAware: version == 4,
      categoryReferences: version >= 5,
      tagsAware: version >= 6,
      merchantsAware: version == 7,
    );
    final db = openEncrypted(
      file,
      key,
      storageBinding: _binding(receipt),
      categoryAware: version == 4,
      categoryReferences: version >= 5,
      tagsAware: version >= 6,
      merchantsAware: version == 7,
    );
    try {
      // Installation fingerprint authenticates the imported input, not the live
      // ledger after later ACID postings. Capture validates its current contents.
      return utf8.decode(await sourceCodec.capture(db));
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
    bool categoryAware = false,
    bool categoryReferences = false,
    bool tagsAware = false,
    this.merchantsAware = false,
    Duration lockTimeout = const Duration(seconds: 10),
  }) : tagsAware = tagsAware || merchantsAware,
       categoryReferences = categoryReferences || tagsAware || merchantsAware,
       categoryAware =
           categoryAware || categoryReferences || tagsAware || merchantsAware,
       generations = GenerationStore(
         directory,
         keys,
         payload: LedgerPayload(
           categoryAware: categoryAware,
           categoryReferences: categoryReferences,
           tagsAware: tagsAware,
           merchantsAware: merchantsAware,
         ),
         upgradeAware:
             categoryAware || categoryReferences || tagsAware || merchantsAware,
         catalogProtection: catalogProtection,
         lockTimeout: lockTimeout,
       );
  final GenerationStore generations;
  final bool categoryAware;
  final bool categoryReferences;
  final bool tagsAware;
  final bool merchantsAware;

  Future<GenerationReceipt> initialize(OperationId operation) =>
      generations.install(
        utf8.decode(
          SnapshotCodec(
            generationAware: true,
            categoryAware: categoryAware,
            categoryReferences: categoryReferences,
            tagsAware: tagsAware,
            merchantsAware: merchantsAware,
          ).empty(),
        ),
        operation,
        onlyIfEmpty: true,
      );

  /// One lifecycle lease; commands are serialized and drained before closing.
  /// Retaining the facade after the callback returns never retains DB access.
  Future<T> withSession<T>(Future<T> Function(LedgerSession) work) async {
    Object? failure;
    StackTrace? trace;
    late T result;
    await generations.withCurrent((file, key, receipt) async {
      final db = openEncrypted(
        file,
        key,
        storageBinding: _binding(receipt),
        categoryAware: categoryAware,
        categoryReferences: categoryReferences,
        tagsAware: tagsAware,
        merchantsAware: merchantsAware,
      );
      final session = LedgerSession._(db);
      try {
        result = await work(session);
      } catch (error, stack) {
        failure = error;
        trace = stack;
      } finally {
        await session._close();
        await db.close();
      }
    });
    if (failure != null) Error.throwWithStackTrace(failure!, trace!);
    return result;
  }

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
    String? recoveryKey,
    LockWaitCancellation? cancellation,
  }) async => EnvelopeCodec().create(
    await snapshot(cancellation: cancellation),
    password: password,
    recoveryKey: recoveryKey,
  );

  Future<T> _use<T>(
    Future<T> Function(ProbeDatabase) work, {
    LockWaitCancellation? cancellation,
  }) => generations.withCurrent((file, key, receipt) async {
    final db = openEncrypted(
      file,
      key,
      storageBinding: _binding(receipt),
      categoryAware: categoryAware,
      categoryReferences: categoryReferences,
      tagsAware: tagsAware,
      merchantsAware: merchantsAware,
    );
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
