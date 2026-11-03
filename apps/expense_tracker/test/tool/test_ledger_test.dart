import 'dart:io';

import 'package:expense_tracker/src/core/ledger/table_journal.dart';
import 'package:expense_tracker/src/features/backup/model/vault_keeper.dart';
import 'package:expense_tracker/src/features/import/model/exchange.dart';
import 'package:expense_tracker/src/features/lock/model/startup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

/// The test backup people restore to try the app with real-looking data:
/// the months of tool/test_ledger.py imported as its CSV would be, kept
/// as a backup that opens with [password]. Every line must import. With
/// TEST_BACKUP_OUT set, as the APK build does, the backup is copied
/// there to be published beside the APK.
void main() {
  const password = 'test1234';

  test('the test ledger imports in full and its backup opens with '
      '$password', () async {
    final work = Directory.systemTemp.createTempSync('test-ledger-');
    addTearDown(() => work.deleteSync(recursive: true));
    final csv = File('${work.path}/ledger.csv');
    final made = await Process.run('python3', [
      'tool/test_ledger.py',
      csv.path,
    ]);
    expect(made.exitCode, 0, reason: '${made.stderr}');

    // The app's own codec: a password of 6 or more, the real key work.
    Startup startupIn(String name) => Startup(
      LedgerVault(
        Directory('${work.path}/$name'),
        codec: KeyringCodec(minimumPassword: 6),
      ),
      check: TableJournal.check,
    );
    final startup = startupIn('made');
    await startup.setUp(password);
    final vault = (startup.state as Ready).vault;
    final ledger = await TableJournal(vault.store).load();
    final found = importCsv(ledger, await csv.readAsString(), fallback: '');
    expect(found.skipped, 0, reason: found.problems.join('\n'));
    expect(found.entries, hasLength(430));
    addImport(ledger, found);
    await ledger.settled;
    expect(ledger.problem.value, isNull);

    final keeper = VaultKeeper(startup, vault);
    final backup = await keeper.backUp();
    await keeper.lock();

    final phone = startupIn('restored');
    await phone.restore(backup, password);
    expect(phone.state, isA<Ready>());
    final restored = await TableJournal(
      (phone.state as Ready).vault.store,
    ).load();
    expect(restored.entries, hasLength(ledger.entries.length));
    phone.lock();

    final out = Platform.environment['TEST_BACKUP_OUT'];
    if (out != null && out.isNotEmpty) File(backup).copySync(out);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
