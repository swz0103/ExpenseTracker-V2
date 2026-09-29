part of 'safety_backup.dart';

/// Schema 21 starts with empty investment authority tables. Historical cash
/// transactions are never inferred into holdings.
Future<UpgradeRequest> planInvestmentUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.investments,
  cancellation: cancellation,
);

Future<UpgradeReceipt> upgradeInvestments(
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
  _LedgerUpgrade.investments,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);
