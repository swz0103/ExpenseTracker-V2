part of 'safety_backup.dart';

const _categoryUpgradeRoute = 'ledger-3-to-4-v1';

/// Capture a retry identity under a lease. A later financial change invalidates
/// this request instead of upgrading a different source behind the caller's back.
Future<UpgradeRequest> planCategoryUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) async {
  final source = await store.generations.current(
    cancellation: cancellation,
    requireExistingCatalog: true,
  );
  if (source == null) throw StateError('No source Ledger');
  _requireCategoryUpgradeSource(source.value);
  return UpgradeRequest(
    operation: operation,
    sourceGeneration: source.receipt.generation,
    sourceDigest: sha256.convert(utf8.encode(source.value)).toString(),
    route: _categoryUpgradeRoute,
    fromVersion: 3,
    toVersion: 4,
    backupId: backupId,
  );
}

void _requireCategoryUpgradeSource(String source) {
  final parsed = jsonDecode(source) as Map;
  if (parsed['version'] != 2 || parsed['schema'] != 3)
    throw const InvalidSnapshot();
  // Exact known modules and columns, before creating a backup or any new DDL.
  SnapshotCodec(generationAware: true).canonicalize(utf8.encode(source));
}

/// Explicit schema 3 -> 4 only. Both retained credentials are required so an
/// interrupted caller can reopen its already persisted backup without a new key.
Future<UpgradeReceipt> upgradeCategories(
  LedgerStore store,
  UpgradeRequest request,
  Directory backupDirectory, {
  required String password,
  required String recoveryKey,
  LockWaitCancellation? cancellation,
  void Function(String)? checkpoint,
}) {
  if (!store.categoryAware ||
      request.route != _categoryUpgradeRoute ||
      request.fromVersion != 3 ||
      request.toVersion != 4)
    throw const InvalidSnapshot();
  return store.generations.upgrade(
    request,
    (source) async {
      _requireCategoryUpgradeSource(source.value);
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
      final target = SnapshotCodec(categoryAware: true)
          .canonicalize(utf8.encode(source.value));
      return PreparedUpgrade(utf8.decode(target), verified.envelopeDigest);
    },
    checkpoint: checkpoint,
    cancellation: cancellation,
  );
}
