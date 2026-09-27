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
      if (version != 3 && version != 4 && version != 5) throw PreviewInvalid();
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
        _ => planTagUpgrade,
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
        _ => upgradeTags,
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
