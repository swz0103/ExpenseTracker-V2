import 'dart:io';

import 'package:cloud_backup_probe/cloud_backup_manual_flow.dart';
import 'package:expense_preview/engine_cloud_backup.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/engine-cloud-backup')
    ..createSync(recursive: true);

  test(
    'engine bridge creates verified artifact and cleanly restores it',
    () async {
      final work = root.createTempSync('case-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 24);
      try {
        final recoveryKey = await setup(engine);
        final cash = account(engine);
        await engine.createAccount(cash, opening(cash));
        final bridge = EngineCloudBackupBridge(
          engine: engine,
          now: () => DateTime.utc(2026, 9, 30, 12),
          backupId: () => 'manual-fixed-id',
        );

        final artifact = await bridge.createSource();
        expect(artifact.backupId, 'manual-fixed-id');
        expect(artifact.createdAt, DateTime.utc(2026, 9, 30, 12));

        await engine.post(income(cash));
        expect(
          (await engine.accounts()).single.balance,
          Money.parse(Currency('TWD', 2), '107'),
        );

        await bridge.restore(
          artifact.envelope,
          CloudBackupCredentialKind.recoveryKey,
          recoveryKey,
        );
        expect(
          (await engine.accounts()).single.balance,
          Money.parse(Currency('TWD', 2), '100'),
        );
        expect(await engine.hasSafetyCopy(), isTrue);
      } finally {
        await engine.lock();
        deleteSynthetic(work, root);
      }
    },
  );
}
