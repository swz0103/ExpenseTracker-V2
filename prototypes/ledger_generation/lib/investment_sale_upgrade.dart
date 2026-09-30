part of 'safety_backup.dart';

/// Schema 22 introduces empty disposition tables. Existing schema-21 buys
/// retain their original lots and are never interpreted as historical sales.
Future<UpgradeRequest> planInvestmentSaleUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.investmentSales,
  cancellation: cancellation,
);

Future<UpgradeReceipt> upgradeInvestmentSales(
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
  _LedgerUpgrade.investmentSales,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);
