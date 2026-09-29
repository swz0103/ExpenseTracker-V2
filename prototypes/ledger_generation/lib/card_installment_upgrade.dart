part of 'safety_backup.dart';

/// Schema 20 adds only plan projections. No plans are inferred from historic
/// purchases. The source is checked again under the generation lease before
/// a verified, dual-credential safety backup and publication.
Future<UpgradeRequest> planCardInstallmentUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.cardInstallments,
  cancellation: cancellation,
);

Future<UpgradeReceipt> upgradeCardInstallments(
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
  _LedgerUpgrade.cardInstallments,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);
