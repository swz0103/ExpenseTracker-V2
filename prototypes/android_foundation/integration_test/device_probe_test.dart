import 'dart:io';

import 'package:android_foundation/android_key_vault.dart';
import 'package:android_foundation/key_access.dart';
import 'package:android_foundation/probe_runner.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:validated_restore_probe/restore_store.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android secure slots, encrypted reopen and paired Ledger restores',
    (tester) async {
      expect(await ProbeRunner().run(), hasLength(3));
      // Export only this public synthetic fixture for later clean-app restores.
      // Credential files are test artifacts, never a production storage design.
      final support = await getApplicationSupportDirectory();
      final root = Directory('${support.path}/foundation_fixture_v1');
      final source = File('${root.path}/current.db');
      final key = await KeyAccess(AndroidKeyVault())
          .load(databaseExists: source.exists);
      final db = openEncrypted(source, key);
      try {
        final bytes = await SnapshotCodec().capture(db);
        final backup = await RestoreStore(root)
            .backup(db, 'android-synthetic-fixture-only');
        final output = Directory('${support.path}/probe_export');
        await output.create();
        await File('${output.path}/envelope.json')
            .writeAsString(backup.envelope, flush: true);
        await File('${output.path}/recovery.txt')
            .writeAsString(backup.recoveryKey, flush: true);
        await File('${output.path}/expected.json')
            .writeAsBytes(bytes, flush: true);
      } finally {
        await db.close();
      }
      // Reuses persisted source key, target pairs and receipts with fresh objects.
      expect(await ProbeRunner().run(), hasLength(3));
    },
  );
}
