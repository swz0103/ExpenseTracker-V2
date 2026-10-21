import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/book/table_journal.dart';
import 'package:expense_tracker/src/book/vault_keeper.dart';
import 'package:expense_tracker/src/model/ledger.dart';
import 'package:expense_tracker/src/startup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

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
      ),
      check: TableJournal.check,
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
    final journal = TableJournal(vaultOf(first).store, clock: clock);
    final ledger = await journal.load();
    final cash = Account(
      ledger.newId(),
      '錢包',
      AccountKind.cash,
      1000,
      icon: 'safe',
    );
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
    final keeper = VaultKeeper(first, vaultOf(first));
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
    final restored = await TableJournal(
      vaultOf(second).store,
      clock: clock,
    ).load();
    expect(restored.balance(cash.id), 800);
    expect(restored.entriesIn(2026, 10), hasLength(2));
    expect(restored.account(cash.id).icon, 'safe');
    expect(restored.category('飲食日常').icon, 'food');
    vaultOf(second).close();
    first.lock();
  });

  test('the password and recovery code can be replaced', () async {
    final startup = startupIn('keys');
    final oldCode = await startup.setUp(password);
    final vault = vaultOf(startup);
    final keeper = VaultKeeper(startup, vault);
    await expectLater(
      keeper.changePassword('not the password at all', changed),
      throwsA(isA<KeyringException>()),
    );
    await keeper.changePassword(password, changed);
    final newCode = await keeper.newRecoveryCode();
    expect(newCode, isNot(oldCode));
    await keeper.lock();
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
    // The code opened it; from now on it opens by itself, as without a
    // password, until one is set again.
    expect(startup.passwordless, isTrue);
    startup.lock();
    await startup.openQuietly();
    expect(startup.state, isA<Ready>());
    startup.lock();
  });

  test('locking keeps the changes still being written', () async {
    final startup = startupIn('pending');
    await startup.setUp(password);
    final vault = vaultOf(startup);
    final journal = TableJournal(vault.store, clock: clock);
    final ledger = await journal.load();
    final keeper = VaultKeeper(
      startup,
      vault,
      beforeLock: () => ledger.settled,
    );
    final cash = Account(ledger.newId(), '錢包', AccountKind.cash, 1000);
    ledger
      ..addAccount(cash)
      ..add(
        Entry(
          id: ledger.newId(),
          date: DateTime.utc(2026, 10, 2),
          type: EntryType.expense,
          amount: 120,
          account: cash.id,
          category: '飲食日常',
        ),
      );
    await keeper.lock();
    expect(startup.state, isA<Locked>());
    expect(ledger.problem.value, isNull);

    await startup.unlockWithPassword(password);
    final again = await TableJournal(
      vaultOf(startup).store,
      clock: clock,
    ).load();
    expect(again.balance(cash.id), 880);
    startup.lock();
  });

  test('a ledger without a password can be given one', () async {
    final startup = startupIn('quiet');
    await startup.setUpWithoutPassword();
    final vault = vaultOf(startup);
    final keeper = VaultKeeper(startup, vault);
    expect(keeper.hasPassword, isFalse);
    await keeper.setPassword(changed);
    expect(keeper.hasPassword, isTrue);
    expect(startup.passwordless, isFalse);
    await keeper.lock();
    await startup.unlockWithPassword(changed);
    expect(startup.state, isA<Ready>());
    startup.lock();
  });
}
