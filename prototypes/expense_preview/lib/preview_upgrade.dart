part of 'preview_engine.dart';

extension _PreviewUpgrade on PreviewEngine {
  /// Each retry inspects the committed generation and resumes only the remaining
  /// known route. A failed attempt retains its old DB/key and backup evidence;
  /// a fresh operation/backup ID avoids overwriting a partially written backup.
  Future<void> _upgradeLedger(
    PublicId identity,
    int from,
    String password,
    String recovery,
    int epoch,
  ) async {
    final backups = Directory('${directory.path}/upgrade-backups');
    await backups.create(recursive: true);
    for (var version = from; version < schemaVersion; version++) {
      if (version != 3 &&
          version != 4 &&
          version != 5 &&
          version != 6 &&
          version != 7 &&
          version != 8 &&
          version != 9 &&
          version != 10 &&
          version != 11 &&
          version != 12 &&
          version != 13 &&
          version != 14 &&
          version != 15) {
        throw PreviewInvalid();
      }
      _check(epoch);
      final target = factory(
        Directory('${directory.path}/ledger'),
        identity,
        version + 1,
      );
      final source = await target.snapshot();
      validatePreviewSnapshot(source, schemaVersion: version + 1);
      _check(epoch);
      final plan = switch (version) {
        3 => planCategoryUpgrade,
        4 => planCategoryReferenceUpgrade,
        5 => planTagUpgrade,
        6 => planMerchantUpgrade,
        7 => planTransferUpgrade,
        8 => planFxTransferUpgrade,
        9 => planRefundUpgrade,
        10 => planReversalUpgrade,
        11 => planNoteUpgrade,
        12 => planCorrectionUpgrade,
        13 => planTombstoneUpgrade,
        14 => planBudgetUpgrade,
        15 => planRecurringUpgrade,
        _ => throw PreviewInvalid(),
      };
      final request = await plan(
        target,
        OperationId(PublicId.generate()),
        PublicId.generate(),
      );
      _check(epoch);
      final upgrade = switch (version) {
        3 => upgradeCategories,
        4 => upgradeCategoryReferences,
        5 => upgradeTags,
        6 => upgradeMerchants,
        7 => upgradeTransfers,
        8 => upgradeFxTransfers,
        9 => upgradeRefunds,
        10 => upgradeReversals,
        11 => upgradeNotes,
        12 => upgradeCorrections,
        13 => upgradeTombstones,
        14 => upgradeBudgets,
        15 => upgradeRecurring,
        _ => throw PreviewInvalid(),
      };
      await upgrade(
        target,
        request,
        backups,
        password: password,
        recoveryKey: recovery,
        checkpoint: (point) {
          _check(epoch);
          upgradeCheckpoint?.call('$version:$point');
          _check(epoch);
        },
      );
      _check(epoch);
    }
  }
}
