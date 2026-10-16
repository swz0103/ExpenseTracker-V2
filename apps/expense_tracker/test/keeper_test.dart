import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:backup_security/backup_security.dart';
import 'package:expense_tracker/src/book/looks.dart';
import 'package:expense_tracker/src/book/vault_journal.dart';
import 'package:expense_tracker/src/book/vault_keeper.dart';
import 'package:expense_tracker/src/demo/ledger.dart';
import 'package:expense_tracker/src/startup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_vault/ledger_vault.dart';

/// Backups, restore and keys of the encrypted ledger, as the settings
/// and lock screens use them.
void main() {
  const password = 'correct horse battery';
  const changed = 'another long passphrase';
  final clock = FixedClock(UtcInstant(DateTime.utc(2026, 10, 3, 4)));
  final directories = <Directory>[];

  tearDown(() {
    for (final d in directories) {
      d.deleteSync(recursive: true);
    }
    directories.clear();
  });

  Startup startupIn(String name) {
    final directory = Directory.systemTemp.createTempSync('keeper-$name-');
    directories.add(directory);
    return Startup(
      LedgerVault(
        directory,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
        modules: [looksSchema],
      ),
      clock: clock,
    );
  }

  OpenVault vaultOf(Startup startup) => switch (startup.state) {
    Ready(:final vault) => vault,
    _ => throw StateError('Not open'),
  };

  test('a backup restores on another device', () async {
    final first = startupIn('first');
    await first.setUp(password);
    expect(first.takeRecoveryCode(), isNotNull);
    expect(first.takeRecoveryCode(), isNull);
    final journal = VaultJournal(vaultOf(first), clock: clock);
    final ledger = await journal.load();
    final cash = Account(ledger.newId(), '錢包', AccountKind.cash, 1000);
    ledger.addAccount(cash);
    await ledger.settled;
    ledger.add(
      Entry(
        id: ledger.newId(),
        date: DateTime.utc(2026, 10, 2),
        type: EntryType.expense,
        amount: 120,
        account: cash.id,
        category: '飲食日常',
      ),
    );
    await ledger.settled;
    expect(ledger.problem.value, isNull);
    final keeper = VaultKeeper(first, vaultOf(first), journal);
    final path = await keeper.backUp();
    expect(path, startsWith(keeper.backupFolder));
    expect(await keeper.backUpIfDue(), isNull);
    expect(await keeper.backUpIfDue(every: Duration.zero), isNull);
    ledger.add(
      Entry(
        id: ledger.newId(),
        date: DateTime.utc(2026, 10, 2),
        type: EntryType.expense,
        amount: 80,
        account: cash.id,
        category: '飲食日常',
      ),
    );
    await ledger.settled;
    final weekly = await keeper.backUpIfDue(every: Duration.zero, keep: 1);
    expect(weekly, isNotNull);
    expect(Directory(keeper.backupFolder).listSync(), hasLength(1));

    final second = startupIn('second');
    expect(second.state, isA<NeedsSetup>());
    expect(File(path).existsSync(), isFalse);
    await second.restore(weekly!, password);
    final restored = await VaultJournal(vaultOf(second), clock: clock).load();
    expect(restored.balance(cash.id), 800);
    expect(restored.entriesIn(2026, 10), hasLength(2));
    vaultOf(second).close();
    first.lock();
  });

  test('the password and recovery code can be replaced', () async {
    final startup = startupIn('keys');
    final oldCode = await startup.setUp(password);
    final vault = vaultOf(startup);
    final keeper = VaultKeeper(startup, vault, VaultJournal(vault));
    await expectLater(
      keeper.changePassword('not the password at all', changed),
      throwsA(isA<KeyringException>()),
    );
    await keeper.changePassword(password, changed);
    final newCode = await keeper.newRecoveryCode();
    expect(newCode, isNot(oldCode));
    keeper.lock();
    expect(startup.state, isA<Locked>());

    await expectLater(
      startup.unlockWithPassword(password),
      throwsA(isA<KeyringException>()),
    );
    await startup.unlockWithPassword(changed);
    startup.lock();
    await expectLater(
      startup.unlockWithRecovery(oldCode),
      throwsA(isA<KeyringException>()),
    );
    await startup.unlockWithRecovery(newCode);
    startup.lock();
  });
}
