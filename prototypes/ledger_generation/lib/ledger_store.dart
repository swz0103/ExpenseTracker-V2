import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:accounts/accounts.dart';
import 'package:categories/categories.dart';
import 'package:data_exchange/data_exchange.dart';
import 'package:tags/tags.dart';
import 'package:merchants/merchants.dart';
import 'package:drift/drift.dart';
import 'package:crypto/crypto.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:reports/reports.dart';
import 'package:budgets/budgets.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:credit_cards/credit_cards.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/adapters.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';
import 'package:modular_persistence_probe/tags_adapter.dart';
import 'package:modular_persistence_probe/merchants_adapter.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:modular_persistence_probe/refunds_adapter.dart';
import 'package:modular_persistence_probe/reversals_adapter.dart';
import 'package:modular_persistence_probe/notes_adapter.dart';
import 'package:modular_persistence_probe/budget_revisions_adapter.dart';
import 'package:modular_persistence_probe/recurring_revisions_adapter.dart';
import 'package:modular_persistence_probe/card_revisions_adapter.dart';
import 'package:modular_persistence_probe/card_statements_adapter.dart'
    as card_facts;
import 'package:modular_persistence_probe/card_authorizations_adapter.dart'
    as card_auth;
import 'package:sqlite3/sqlite3.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:storage_generation_probe/key_slots.dart';
import 'package:storage_generation_probe/lock_wait.dart';
import 'package:storage_generation_probe/catalog_protection.dart';
import 'package:validated_restore_probe/snapshot.dart';

export 'package:modular_persistence_probe/card_statements_adapter.dart'
    show ConfirmedCardStatement, CardUnallocatedPayment;
export 'package:modular_persistence_probe/card_authorizations_adapter.dart'
    show CardAuthorizationFact, CardAuthorizationState;

part 'ledger_session.dart';
part 'simple_import_session.dart';
part 'activity_session.dart';
part 'note_session.dart';
part 'category_session.dart';
part 'tag_session.dart';
part 'tag_references.dart';
part 'merchant_session.dart';
part 'merchant_references.dart';
part 'allocation_session.dart';
part 'session_capacity.dart';
part 'budget_session.dart';
part 'recurring_session.dart';

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
    bool merchantsAware = false,
    bool transfersAware = false,
    bool fxTransfersAware = false,
    bool refundsAware = false,
    bool reversalsAware = false,
    bool notesAware = false,
    this.correctionsAware = false,
    this.tombstonesAware = false,
    this.budgetsAware = false,
    this.recurringAware = false,
    this.creditCardsAware = false,
    this.cardStatementsAware = false,
    this.cardAuthorizationsAware = false,
  }) : notesAware = notesAware || correctionsAware,
       reversalsAware = reversalsAware || notesAware || correctionsAware,
       refundsAware =
           refundsAware || reversalsAware || notesAware || correctionsAware,
       fxTransfersAware =
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       transfersAware =
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       merchantsAware =
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       tagsAware =
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       categoryReferences =
           categoryReferences ||
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       categoryAware =
           categoryAware ||
           categoryReferences ||
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       codec = SnapshotCodec(
         generationAware: true,
         categoryAware: categoryAware,
         categoryReferences: categoryReferences,
         tagsAware: tagsAware,
         merchantsAware: merchantsAware,
         transfersAware: transfersAware,
         fxTransfersAware: fxTransfersAware,
         refundsAware:
             refundsAware || reversalsAware || notesAware || correctionsAware,
         reversalsAware: reversalsAware,
         notesAware: notesAware,
         correctionsAware: correctionsAware,
         tombstonesAware: tombstonesAware,
         budgetsAware: budgetsAware,
         recurringAware: recurringAware,
         creditCardsAware: creditCardsAware,
         cardStatementsAware: cardStatementsAware,
         cardAuthorizationsAware: cardAuthorizationsAware,
       );
  final bool categoryAware;
  final bool categoryReferences;
  final bool tagsAware;
  final bool merchantsAware;
  final bool transfersAware;
  final bool fxTransfersAware;
  final bool refundsAware;
  final bool reversalsAware;
  final bool notesAware;
  final bool correctionsAware;
  final bool tombstonesAware;
  final bool budgetsAware;
  final bool recurringAware;
  final bool creditCardsAware;
  final bool cardStatementsAware;
  final bool cardAuthorizationsAware;
  final SnapshotCodec codec;
  @override
  int get maxBytes => EnvelopeCodec.maxPayloadBytes;
  @override
  String canonicalize(String input) {
    if (cardAuthorizationsAware) {
      // The snapshot codec can add empty v19 tables to a v18 manifest, but
      // installation must use the explicit safety-backed 18 -> 19 route.
      Object? source;
      try {
        source = jsonDecode(input);
      } catch (_) {
        throw const InvalidSnapshot();
      }
      if (source is! Map || source['schema'] != 19 || source['version'] != 18) {
        throw const InvalidSnapshot();
      }
    }
    return utf8.decode(codec.canonicalize(utf8.encode(input)));
  }

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
      transfersAware: transfersAware,
      fxTransfersAware: fxTransfersAware,
      refundsAware:
          refundsAware || reversalsAware || notesAware || correctionsAware,
      reversalsAware: reversalsAware,
      notesAware: notesAware,
      correctionsAware: correctionsAware,
      tombstonesAware: tombstonesAware,
      budgetsAware: budgetsAware,
      recurringAware: recurringAware,
      creditCardsAware: creditCardsAware,
      cardStatementsAware: cardStatementsAware,
      cardAuthorizationsAware: cardAuthorizationsAware,
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
              (merchantsAware && version == 7) ||
              (transfersAware && version == 8) ||
              (fxTransfersAware && version == 9) ||
              (refundsAware && version == 10) ||
              (reversalsAware && version == 11) ||
              (notesAware && version == 12) ||
              (correctionsAware && version == 13) ||
              (tombstonesAware && version == 14) ||
              (budgetsAware && version == 15) ||
              (recurringAware && version == 16) ||
              (creditCardsAware && version == 17) ||
              (cardStatementsAware && version == 18) ||
              (cardAuthorizationsAware && version == 19)) ||
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
      merchantsAware: version >= 7,
      transfersAware: version >= 8,
      fxTransfersAware: version >= 9,
      refundsAware: version >= 10,
      reversalsAware: version >= 11,
      notesAware: version >= 12,
      correctionsAware: version >= 13,
      tombstonesAware: version >= 14,
      budgetsAware: version >= 15,
      recurringAware: version >= 16,
      creditCardsAware: version >= 17,
      cardStatementsAware: version >= 18,
      cardAuthorizationsAware: version >= 19,
    );
    final db = openEncrypted(
      file,
      key,
      storageBinding: _binding(receipt),
      categoryAware: version == 4,
      categoryReferences: version >= 5,
      tagsAware: version >= 6,
      merchantsAware: version >= 7,
      transfersAware: version >= 8,
      fxTransfersAware: version >= 9,
      refundsAware: version >= 10,
      reversalsAware: version >= 11,
      notesAware: version >= 12,
      correctionsAware: version >= 13,
      tombstonesAware: version >= 14,
      budgetsAware: version >= 15,
      recurringAware: version >= 16,
      creditCardsAware: version >= 17,
      cardStatementsAware: version >= 18,
      cardAuthorizationsAware: version >= 19,
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
    bool merchantsAware = false,
    bool transfersAware = false,
    bool fxTransfersAware = false,
    bool refundsAware = false,
    bool reversalsAware = false,
    bool notesAware = false,
    this.correctionsAware = false,
    this.tombstonesAware = false,
    this.budgetsAware = false,
    this.recurringAware = false,
    this.creditCardsAware = false,
    this.cardStatementsAware = false,
    this.cardAuthorizationsAware = false,
    Duration lockTimeout = const Duration(seconds: 10),
  }) : notesAware = notesAware || correctionsAware,
       reversalsAware = reversalsAware || notesAware || correctionsAware,
       refundsAware =
           refundsAware || reversalsAware || notesAware || correctionsAware,
       fxTransfersAware =
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       transfersAware =
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       merchantsAware =
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       tagsAware =
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       categoryReferences =
           categoryReferences ||
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       categoryAware =
           categoryAware ||
           categoryReferences ||
           tagsAware ||
           merchantsAware ||
           transfersAware ||
           fxTransfersAware ||
           refundsAware ||
           reversalsAware ||
           notesAware ||
           correctionsAware,
       generations = GenerationStore(
         directory,
         keys,
         payload: LedgerPayload(
           categoryAware: categoryAware,
           categoryReferences: categoryReferences,
           tagsAware: tagsAware,
           merchantsAware: merchantsAware,
           transfersAware: transfersAware,
           fxTransfersAware: fxTransfersAware,
           refundsAware:
               refundsAware || reversalsAware || notesAware || correctionsAware,
           reversalsAware: reversalsAware,
           notesAware: notesAware,
           correctionsAware: correctionsAware,
           tombstonesAware: tombstonesAware,
           budgetsAware: budgetsAware,
           recurringAware: recurringAware,
           creditCardsAware: creditCardsAware,
           cardStatementsAware: cardStatementsAware,
           cardAuthorizationsAware: cardAuthorizationsAware,
         ),
         upgradeAware:
             categoryAware ||
             categoryReferences ||
             tagsAware ||
             merchantsAware ||
             transfersAware ||
             fxTransfersAware ||
             refundsAware ||
             reversalsAware ||
             notesAware ||
             correctionsAware ||
             tombstonesAware ||
             budgetsAware ||
             recurringAware ||
             creditCardsAware ||
             cardStatementsAware ||
             cardAuthorizationsAware,
         catalogProtection: catalogProtection,
         lockTimeout: lockTimeout,
       );
  final GenerationStore generations;
  final bool categoryAware;
  final bool categoryReferences;
  final bool tagsAware;
  final bool merchantsAware;
  final bool transfersAware;
  final bool fxTransfersAware;
  final bool refundsAware;
  final bool reversalsAware;
  final bool notesAware;
  final bool correctionsAware;
  final bool tombstonesAware;
  final bool budgetsAware;
  final bool recurringAware;
  final bool creditCardsAware;
  final bool cardStatementsAware;
  final bool cardAuthorizationsAware;

  Future<GenerationReceipt> initialize(OperationId operation) =>
      generations.install(
        utf8.decode(
          SnapshotCodec(
            generationAware: true,
            categoryAware: categoryAware,
            categoryReferences: categoryReferences,
            tagsAware: tagsAware,
            merchantsAware: merchantsAware,
            transfersAware: transfersAware,
            fxTransfersAware: fxTransfersAware,
            refundsAware:
                refundsAware ||
                reversalsAware ||
                notesAware ||
                correctionsAware,
            reversalsAware: reversalsAware,
            notesAware: notesAware,
            correctionsAware: correctionsAware,
            tombstonesAware: tombstonesAware,
            budgetsAware: budgetsAware,
            recurringAware: recurringAware,
            creditCardsAware: creditCardsAware,
            cardStatementsAware: cardStatementsAware,
            cardAuthorizationsAware: cardAuthorizationsAware,
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
        transfersAware: transfersAware,
        fxTransfersAware: fxTransfersAware,
        refundsAware:
            refundsAware || reversalsAware || notesAware || correctionsAware,
        reversalsAware: reversalsAware,
        notesAware: notesAware,
        correctionsAware: correctionsAware,
        tombstonesAware: tombstonesAware,
        budgetsAware: budgetsAware,
        recurringAware: recurringAware,
        creditCardsAware: creditCardsAware,
        cardStatementsAware: cardStatementsAware,
        cardAuthorizationsAware: cardAuthorizationsAware,
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
      transfersAware: transfersAware,
      fxTransfersAware: fxTransfersAware,
      refundsAware:
          refundsAware || reversalsAware || notesAware || correctionsAware,
      reversalsAware: reversalsAware,
      notesAware: notesAware,
      correctionsAware: correctionsAware,
      tombstonesAware: tombstonesAware,
      budgetsAware: budgetsAware,
      recurringAware: recurringAware,
      creditCardsAware: creditCardsAware,
      cardStatementsAware: cardStatementsAware,
      cardAuthorizationsAware: cardAuthorizationsAware,
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
  }) => _use((db) async {
    await _rejectUntrackedCardPosting(db, posting);
    return FinancialWorkflows(db).post(posting);
  }, cancellation: cancellation);
  Future<Money> balance(
    PostingAccount account, {
    LockWaitCancellation? cancellation,
  }) => _use(
    (db) => FinancialWorkflows(db).ledger.balance(account),
    cancellation: cancellation,
  );
}
