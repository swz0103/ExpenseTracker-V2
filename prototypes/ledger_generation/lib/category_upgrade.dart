part of 'safety_backup.dart';

// Known routes share backup/publication without accepting arbitrary versions.
enum _LedgerUpgrade {
  categories(3, 4, 'ledger-3-to-4-v1'),
  references(4, 5, 'ledger-4-to-5-v1'),
  tags(5, 6, 'ledger-5-to-6-v1'),
  merchants(6, 7, 'ledger-6-to-7-v1');

  const _LedgerUpgrade(this.from, this.to, this.route);
  final int from, to;
  final String route;
  SnapshotCodec get target => SnapshotCodec(
    categoryAware: true,
    categoryReferences: to >= 5,
    tagsAware: to >= 6,
    merchantsAware: this == merchants,
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
    ).canonicalize(utf8.encode(source));
  }

  void requireTarget(LedgerStore store) {
    if (!store.categoryAware ||
        store.categoryReferences != (to >= 5) ||
        store.tagsAware != (to >= 6) ||
        store.merchantsAware != (this == merchants)) {
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
