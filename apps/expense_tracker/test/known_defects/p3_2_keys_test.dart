// Work package 3.2: the key held next to the ledger. Fixed in 3.2; kept as
// regression tests of SEC-01 and SEC-04.
import 'dart:io';

import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('p3-'));
  tearDown(() => dir.deleteSync(recursive: true));

  LedgerVault vault() =>
      LedgerVault(dir, codec: KeyringCodec(kdf: PasswordKdf.insecureForTests));

  test('SEC-01: the passwordless mode leaves no unlock secret in a file beside '
      'the ledger', () async {
    final startup = Startup(vault());
    await startup.setUpWithoutPassword();
    (startup.state as Ready).vault.close();
    expect(File('${dir.path}/quick-open.key').existsSync(), isFalse);
  });

  test(
    'SEC-04: unlocking with the recovery code does not drop the password',
    () async {
      final first = Startup(vault());
      final code = await first.setUp('correct horse battery');
      first.lock();
      final startup = Startup(vault());
      await startup.unlockWithRecovery(code);
      // The ledger had a password, and still asks for one.
      expect(startup.passwordless, isFalse);
      expect(File('${dir.path}/quick-open.key').existsSync(), isFalse);
    },
  );
}
