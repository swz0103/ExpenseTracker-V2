part of 'safety_backup.dart';

/// Schema 23 adds an empty authoritative dividend table. Historical cash
/// movements are never inferred as broker dividends during the upgrade.
Future<UpgradeRequest> planInvestmentDividendUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.investmentDividends,
  cancellation: cancellation,
);

Future<UpgradeReceipt> upgradeInvestmentDividends(
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
  _LedgerUpgrade.investmentDividends,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);
