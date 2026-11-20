import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/features/backup/model/encrypted_backup_manager.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
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
    final directory = Directory.systemTemp.createTempSync(
      'backupManager-$name-',
    );
    directories.add(directory);
    return Startup(
      LedgerVault(
        directory,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      ),
      check: SqlLedgerDataSource.check,
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
    final dataSource = SqlLedgerDataSource(vaultOf(first).store, clock: clock);
    final ledger = await dataSource.load();
    final cash = Account(
      ledger.newId(),
      '錢包',
      AccountKind.cash,
      1000,
      icon: 'safe',
    );
    ledger.accountCommands.addAccount(cash);
    await ledger.settled;
    ledger.entryCommands.add(
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
    final backupManager = EncryptedBackupManager(first, vaultOf(first));
    final path = await backupManager.backUp();
    expect(path, startsWith(backupManager.backupFolder));
    expect(await backupManager.backUpIfDue(), isNull);
    expect(await backupManager.backUpIfDue(every: Duration.zero), isNull);
    ledger.entryCommands.add(
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
    final weekly = await backupManager.backUpIfDue(
      every: Duration.zero,
      keep: 1,
    );
    expect(weekly, isNotNull);
    expect(Directory(backupManager.backupFolder).listSync(), hasLength(1));

    final second = startupIn('second');
    expect(second.state, isA<NeedsSetup>());
    expect(File(path).existsSync(), isFalse);
    await second.restore(weekly!, password);
    final restored = await SqlLedgerDataSource(
      vaultOf(second).store,
      clock: clock,
    ).load();
    expect(restored.balanceService.balance(cash.id), 800);
    expect(restored.entries.inMonth(2026, 10), hasLength(2));
    expect(restored.account(cash.id).icon, 'safe');
    expect(restored.category('飲食日常').icon, 'food');
    vaultOf(second).close();
    first.lock();
  });

  test('the password and recovery code can be replaced', () async {
    final startup = startupIn('keys');
    final oldCode = await startup.setUp(password);
    final vault = vaultOf(startup);
    final backupManager = EncryptedBackupManager(startup, vault);
    await expectLater(
      backupManager.changePassword('not the password at all', changed),
      throwsA(isA<KeyringException>()),
    );
    await backupManager.changePassword(password, changed);
    final newCode = await backupManager.newRecoveryCode();
    expect(newCode, isNot(oldCode));
    await backupManager.lock();
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
    final dataSource = SqlLedgerDataSource(vault.store, clock: clock);
    final ledger = await dataSource.load();
    final backupManager = EncryptedBackupManager(
      startup,
      vault,
      beforeLock: () => ledger.settled,
    );
    final cash = Account(ledger.newId(), '錢包', AccountKind.cash, 1000);
    ledger
      ..accountCommands.addAccount(cash)
      ..entryCommands.add(
        Entry(
          id: ledger.newId(),
          date: DateTime.utc(2026, 10, 2),
          type: EntryType.expense,
          amount: 120,
          account: cash.id,
          category: '飲食日常',
        ),
      );
    await backupManager.lock();
    expect(startup.state, isA<Locked>());
    expect(ledger.problem.value, isNull);

    await startup.unlockWithPassword(password);
    final again = await SqlLedgerDataSource(
      vaultOf(startup).store,
      clock: clock,
    ).load();
    expect(again.balanceService.balance(cash.id), 880);
    startup.lock();
  });

  test('a ledger without a password can be given one', () async {
    final startup = startupIn('quiet');
    await startup.setUpWithoutPassword();
    final vault = vaultOf(startup);
    final backupManager = EncryptedBackupManager(startup, vault);
    expect(backupManager.hasPassword, isFalse);
    await backupManager.setPassword(changed);
    expect(backupManager.hasPassword, isTrue);
    expect(startup.passwordless, isFalse);
    await backupManager.lock();
    await startup.unlockWithPassword(changed);
    expect(startup.state, isA<Ready>());
    startup.lock();
  });

  test('the copy for Android\'s backup is written once per change, '
      'without the photos, and restores', () async {
    final startup = startupIn('cloud');
    await startup.setUp(password);
    final vault = vaultOf(startup);
    final backupManager = EncryptedBackupManager(startup, vault);
    final dataSource = SqlLedgerDataSource(vault.store, clock: clock);
    final ledger = await dataSource.load();
    await ledger.settled;
    expect(backupManager.cloudCopyAt, isNull);
    expect(await backupManager.keepCloudCopy(), isTrue);
    expect(backupManager.cloudCopyAt, isNotNull);
    // Written, not yet taken: Android's agent writes down when it takes it.
    expect(backupManager.googleTakenAt, isNull);
    File('${startup.directory.path}/google-backup-taken')
        .writeAsStringSync('1763000000000');
    expect(
      backupManager.googleTakenAt,
      DateTime.fromMillisecondsSinceEpoch(1763000000000),
    );
    expect(
      await backupManager.keepCloudCopy(),
      isFalse,
      reason: 'nothing changed',
    );
    final receipts = Directory('${startup.directory.path}/receipts')
      ..createSync();
    File('${receipts.path}/photo.bin').writeAsBytesSync([1, 2, 3]);
    ledger.accountCommands.addAccount(
      Account(ledger.newId(), '錢包', AccountKind.cash, 0, icon: 'safe'),
    );
    await ledger.settled;
    expect(await backupManager.keepCloudCopy(), isTrue);
    expect(startup.cloudCopy.parent.listSync(), hasLength(1));
    final copy = startup.cloudCopy.path;
    await backupManager.lock();

    final phone = startupIn('new-phone');
    await phone.restore(copy, password);
    expect(phone.state, isA<Ready>());
    expect(
      Directory('${phone.directory.path}/receipts').existsSync(),
      isFalse,
      reason: 'no photos in the copy',
    );
    phone.lock();
  });
}
