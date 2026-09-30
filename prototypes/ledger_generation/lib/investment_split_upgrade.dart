part of 'safety_backup.dart';

/// Schema 24 adds empty split facts; historical quantity is never inferred.
Future<UpgradeRequest> planInvestmentSplitUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.investmentSplits,
  cancellation: cancellation,
);

Future<UpgradeReceipt> upgradeInvestmentSplits(
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
  _LedgerUpgrade.investmentSplits,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);
