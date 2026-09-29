part of 'safety_backup.dart';

// Known routes share backup/publication without accepting arbitrary versions.
enum _LedgerUpgrade {
  categories(3, 4, 'ledger-3-to-4-v1'),
  references(4, 5, 'ledger-4-to-5-v1'),
  tags(5, 6, 'ledger-5-to-6-v1'),
  merchants(6, 7, 'ledger-6-to-7-v1'),
  transfers(7, 8, 'ledger-7-to-8-v1'),
  fxTransfers(8, 9, 'ledger-8-to-9-v1'),
  refunds(9, 10, 'ledger-9-to-10-v1'),
  reversals(10, 11, 'ledger-10-to-11-v1'),
  notes(11, 12, 'ledger-11-to-12-v1'),
  corrections(12, 13, 'ledger-12-to-13-v1'),
  tombstones(13, 14, 'ledger-13-to-14-v1'),
  budgets(14, 15, 'ledger-14-to-15-v1'),
  recurring(15, 16, 'ledger-15-to-16-v1');

  const _LedgerUpgrade(this.from, this.to, this.route);
  final int from, to;
  final String route;
  SnapshotCodec get target => SnapshotCodec(
    categoryAware: true,
    categoryReferences: to >= 5,
    tagsAware: to >= 6,
    merchantsAware: to >= 7,
    transfersAware: to >= 8,
    fxTransfersAware: to >= 9,
    refundsAware: to >= 10,
    reversalsAware: to >= 11,
    notesAware: to >= 12,
    correctionsAware: to >= 13,
    tombstonesAware: to >= 14,
    budgetsAware: to >= 15,
    recurringAware: to >= 16,
  );
  void requireSource(String source) {
    final parsed = jsonDecode(source) as Map;
    if (parsed['version'] != from - 1 || parsed['schema'] != from)
      throw const InvalidSnapshot();
    SnapshotCodec(
      generationAware: true,
      categoryAware: from >= 4,
      categoryReferences: from >= 5,
      tagsAware: from >= 6,
      merchantsAware: from >= 7,
      transfersAware: from >= 8,
      fxTransfersAware: from >= 9,
      refundsAware: from >= 10,
      reversalsAware: from >= 11,
      notesAware: from >= 12,
      correctionsAware: from >= 13,
      tombstonesAware: from >= 14,
      budgetsAware: from >= 15,
      recurringAware: from >= 16,
    ).canonicalize(utf8.encode(source));
  }

  void requireTarget(LedgerStore store) {
    if (!store.categoryAware ||
        store.categoryReferences != (to >= 5) ||
        store.tagsAware != (to >= 6) ||
        store.merchantsAware != (to >= 7) ||
        store.transfersAware != (to >= 8) ||
        store.fxTransfersAware != (to >= 9) ||
        store.refundsAware != (to >= 10) ||
        store.reversalsAware != (to >= 11) ||
        store.notesAware != (to >= 12) ||
        store.correctionsAware != (to >= 13) ||
        store.tombstonesAware != (to >= 14) ||
        store.budgetsAware != (to >= 15) ||
        store.recurringAware != (to >= 16)) {
      throw const InvalidSnapshot();
    }
  }
}

/// Captures live source identity under a lease; later changes invalidate it.
Future<UpgradeRequest> planCategoryUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.categories,
  cancellation: cancellation,
);

Future<UpgradeRequest> planCategoryReferenceUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.references,
  cancellation: cancellation,
);

Future<UpgradeRequest> planTagUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.tags,
  cancellation: cancellation,
);

Future<UpgradeRequest> planMerchantUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.merchants,
  cancellation: cancellation,
);

Future<UpgradeRequest> planTransferUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.transfers,
  cancellation: cancellation,
);

Future<UpgradeRequest> planFxTransferUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.fxTransfers,
  cancellation: cancellation,
);

Future<UpgradeRequest> planRefundUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.refunds,
  cancellation: cancellation,
);

Future<UpgradeRequest> _planUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId,
  _LedgerUpgrade route, {
  LockWaitCancellation? cancellation,
}) async {
  route.requireTarget(store);
  final source = await store.generations.current(
    cancellation: cancellation,
    requireExistingCatalog: true,
  );
  if (source == null) throw StateError('No source Ledger');
  route.requireSource(source.value);
  return UpgradeRequest(
    operation: operation,
    sourceGeneration: source.receipt.generation,
    sourceDigest: sha256.convert(utf8.encode(source.value)).toString(),
    route: route.route,
    fromVersion: route.from,
    toVersion: route.to,
    backupId: backupId,
  );
}

/// Explicit schema 3 -> 4; both retained credentials protect backup retry.
Future<UpgradeReceipt> upgradeCategories(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) => _upgradeLedger(
  store,
  request,
  backupDirectory,
  _LedgerUpgrade.categories,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);

/// Explicit schema 4 -> 5; the old generation/key remain intact.
Future<UpgradeReceipt> upgradeCategoryReferences(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) => _upgradeLedger(
  store,
  request,
  backupDirectory,
  _LedgerUpgrade.references,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);

Future<UpgradeReceipt> upgradeTags(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) => _upgradeLedger(
  store,
  request,
  backupDirectory,
  _LedgerUpgrade.tags,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);

Future<UpgradeReceipt> upgradeMerchants(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) => _upgradeLedger(
  store,
  request,
  backupDirectory,
  _LedgerUpgrade.merchants,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);

Future<UpgradeReceipt> upgradeTransfers(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) => _upgradeLedger(
  store,
  request,
  backupDirectory,
  _LedgerUpgrade.transfers,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);

Future<UpgradeReceipt> upgradeFxTransfers(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) => _upgradeLedger(
  store,
  request,
  backupDirectory,
  _LedgerUpgrade.fxTransfers,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);

Future<UpgradeReceipt> upgradeRefunds(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) => _upgradeLedger(
  store,
  request,
  backupDirectory,
  _LedgerUpgrade.refunds,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);

Future<UpgradeReceipt> _upgradeLedger(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory,
  _LedgerUpgrade route, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) {
  route.requireTarget(store);
  if (request.route != route.route ||
      request.fromVersion != route.from ||
      request.toVersion != route.to)
    throw const InvalidSnapshot();
  return store.generations.upgrade(
    request,
    (source) async {
      route.requireSource(source.value);
      final verified = await _persistSafetyBackup(
        store,
        backupDirectory,
        request.backupId,
        source.receipt,
        source.value,
        password: password,
        recoveryKey: recoveryKey,
        reuseExisting: true,
        checkpoint: (point, _) async {
          checkpoint?.call('backup:$point');
        },
      );
      final target = route.target.canonicalize(utf8.encode(source.value));
      return PreparedUpgrade(utf8.decode(target), verified.envelopeDigest);
    },
    checkpoint: checkpoint,
    cancellation: cancellation,
  );
}

Future<UpgradeRequest> planReversalUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.reversals,
  cancellation: cancellation,
);

Future<UpgradeReceipt> upgradeReversals(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) => _upgradeLedger(
  store,
  request,
  backupDirectory,
  _LedgerUpgrade.reversals,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);
Future<UpgradeRequest> planNoteUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.notes,
  cancellation: cancellation,
);

Future<UpgradeReceipt> upgradeNotes(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) => _upgradeLedger(
  store,
  request,
  backupDirectory,
  _LedgerUpgrade.notes,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);

Future<UpgradeRequest> planCorrectionUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.corrections,
  cancellation: cancellation,
);

Future<UpgradeReceipt> upgradeCorrections(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) => _upgradeLedger(
  store,
  request,
  backupDirectory,
  _LedgerUpgrade.corrections,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);

Future<UpgradeRequest> planTombstoneUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.tombstones,
  cancellation: cancellation,
);

Future<UpgradeReceipt> upgradeTombstones(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) => _upgradeLedger(
  store,
  request,
  backupDirectory,
  _LedgerUpgrade.tombstones,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);

Future<UpgradeRequest> planBudgetUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.budgets,
  cancellation: cancellation,
);

Future<UpgradeReceipt> upgradeBudgets(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) => _upgradeLedger(
  store,
  request,
  backupDirectory,
  _LedgerUpgrade.budgets,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);

Future<UpgradeRequest> planRecurringUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.recurring,
  cancellation: cancellation,
);

Future<UpgradeReceipt> upgradeRecurring(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) => _upgradeLedger(
  store,
  request,
  backupDirectory,
  _LedgerUpgrade.recurring,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);
