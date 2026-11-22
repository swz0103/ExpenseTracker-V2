// Work packages 3.1 and 3.2: locking and the key held next to the ledger.
import 'dart:io';

import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import 'known_defect.dart';

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
  }, skip: knownDefect('SEC-01', '3.2'));

  test(
    'SEC-03: after ten wrong passwords the right one is not accepted at once',
    () async {
      const password = 'correct horse battery';
      final first = Startup(vault());
      await first.setUp(password);
      first.lock();
      final startup = Startup(vault());
      for (var i = 0; i < 10; i++) {
        try {
          await startup.unlockWithPassword('wrong password $i');
        } on KeyringException {
          // Each wrong one is refused.
        }
      }
      try {
        await startup.unlockWithPassword(password);
      } on Object {
        // A lock-out may refuse by throwing.
      }
      expect(startup.state, isNot(isA<Ready>()));
    },
    skip: knownDefect('SEC-03', '3.1'),
  );

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
    skip: knownDefect('SEC-04', '3.2'),
  );
}
