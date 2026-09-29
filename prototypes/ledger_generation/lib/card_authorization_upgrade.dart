part of 'safety_backup.dart';

/// Schema 18 has posted card facts but no pending authorization history.
/// The schema 19 tables begin empty; prior charges are never guessed to have
/// had an authorization. The planned source and route are checked again under
/// the generation lease before the verified, dual-credential safety backup.
Future<UpgradeRequest> planCardAuthorizationUpgrade(
  LedgerStore store,
  OperationId operation,
  PublicId backupId, {
  LockWaitCancellation? cancellation,
}) => _planUpgrade(
  store,
  operation,
  backupId,
  _LedgerUpgrade.cardAuthorizations,
  cancellation: cancellation,
);

Future<UpgradeReceipt> upgradeCardAuthorizations(
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
  _LedgerUpgrade.cardAuthorizations,
  password: password,
  recoveryKey: recoveryKey,
  cancellation: cancellation,
  checkpoint: checkpoint,
);
