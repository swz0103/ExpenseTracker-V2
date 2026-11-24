import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/features/backup/model/backup_manager.dart';
import 'package:expense_tracker/src/features/backup/model/encrypted_backup_manager.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:expense_tracker/src/core/time/app_clock.dart';
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

  test('a copy kept before an upgrade is offered to restore, the last two '
      'kept', () async {
    final startup = startupIn('upgrade');
    await startup.setUp(password);
    final backupManager = EncryptedBackupManager(startup, vaultOf(startup));
    final kept = [
      for (var i = 0; i < 3; i++) await backupManager.keepBeforeUpgrade(),
    ];
    expect(kept.first.existsSync(), isFalse);
    expect(kept.skip(1).every((f) => f.existsSync()), isTrue);
    expect(kept.last.uri.pathSegments.last, startsWith('before-upgrade-'));
    expect(startup.keptBeforeRestore().map((f) => f.path).toSet(), {
      kept[1].path,
      kept[2].path,
    });
    vaultOf(startup).close();
  });

  test('a backup restores on another device', () async {
    final first = startupIn('first');
    final code = await first.setUp(password);
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
    expect(path, startsWith('${first.directory.path}/backups'));
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
    expect(
      Directory('${first.directory.path}/backups').listSync(),
      hasLength(1),
    );

    final second = startupIn('second');
    expect(second.state, isA<NeedsSetup>());
    expect(File(path).existsSync(), isFalse);
    // A backup opens with its recovery code, not the app password.
    await second.restore(weekly!, code, recovery: true);
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
      throwsA(
        isA<KeyRefused>().having((e) => e.message, 'message', '目前的密碼不正確'),
      ),
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
    // The code opened it; the password stays until a new one is set.
    expect(startup.passwordless, isFalse);
    expect(startup.needsNewPassword, isTrue);
    startup.lock();
    await startup.unlockWithPassword(changed);
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
    final code = await startup.setUp(password);
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
    await phone.restore(copy, code, recovery: true);
    expect(phone.state, isA<Ready>());
    expect(
      Directory('${phone.directory.path}/receipts').existsSync(),
      isFalse,
      reason: 'no photos in the copy',
    );
    phone.lock();
  });

  group('two backups asked for at once (F65)', () {
    // Every backup is taken at the same millisecond, as two asked for in
    // one tick are.
    setUp(() => AppClock.use(clock));
    tearDown(AppClock.reset);

    test('the copy for Android\'s backup asked for twice at once is '
        'written once, and neither fails', () async {
      final startup = startupIn('cloud-twice');
      await startup.setUp(password);
      final backupManager = EncryptedBackupManager(startup, vaultOf(startup));
      final ledger = await SqlLedgerDataSource(
        vaultOf(startup).store,
        clock: clock,
      ).load();
      await ledger.settled;
      // Before the fix the second rename found its file gone:
      // PathNotFoundException (errno 2).
      final written = await Future.wait([
        backupManager.keepCloudCopy(),
        backupManager.keepCloudCopy(),
      ]);
      expect(written, [true, false]);
      expect(startup.cloudCopy.existsSync(), isTrue);
      expect(startup.cloudCopy.parent.listSync(), hasLength(1));
      expect(
        Directory('${startup.directory.path}/exports').listSync(),
        isEmpty,
        reason: 'nothing half written is left behind',
      );
      startup.lock();
    });

    test('backups written in the same millisecond each keep a file of '
        'their own', () async {
      final startup = startupIn('same-ms');
      await startup.setUp(password);
      final backupManager = EncryptedBackupManager(startup, vaultOf(startup));
      final paths = await Future.wait([
        backupManager.backUp(),
        backupManager.backUp(),
        backupManager.backUp(),
      ]);
      // 2026-10-03 04:00 UTC is 記帳本-<day>-<hhmmss><ms>; the second and
      // third of the same millisecond take -2 and -3.
      final names = [for (final p in paths) File(p).uri.pathSegments.last];
      expect(names.toSet(), hasLength(3));
      expect(names[1], endsWith('-2.etbk'));
      expect(names[2], endsWith('-3.etbk'));
      expect(
        Directory('${startup.directory.path}/backups')
            .listSync()
            .where((f) => f.path.endsWith('.part')),
        isEmpty,
      );
      startup.lock();
    });
  });

  group('the fingerprint switch (F39)', () {
    /// A ledger with a password on a phone that has a fingerprint key.
    Future<(Startup, EncryptedBackupManager)> onPhone(String name) async {
      final plain = startupIn(name);
      final startup = Startup(
        LedgerVault(
          plain.directory,
          codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
        ),
        device: DeviceUnlock('phone', _Key()),
      );
      await startup.setUp(password);
      return (startup, EncryptedBackupManager(startup, vaultOf(startup)));
    }

    test('it is there on a phone with a fingerprint, on once the password '
        'set it up; off, the fingerprint no longer opens the ledger; on '
        'again, it does', () async {
      final (startup, backupManager) = await onPhone('finger');
      expect(backupManager.canUseFingerprint, isTrue);
      expect(backupManager.fingerprintOn, isTrue);

      expect(await backupManager.turnFingerprint(on: false), isTrue);
      expect(backupManager.fingerprintOn, isFalse);
      startup.lock();
      await expectLater(
        startup.unlockWithDevice(),
        throwsA(const KeyringException(KeyringError.unknownDevice)),
      );
      await startup.unlockWithPassword(password);
      final again = EncryptedBackupManager(startup, vaultOf(startup));
      expect(again.fingerprintOn, isFalse, reason: 'not brought back');

      expect(await again.turnFingerprint(on: true), isTrue);
      expect(again.fingerprintOn, isTrue);
      startup.lock();
      expect(await startup.unlockWithDevice(), isTrue);
      startup.lock();
    });

    test('a phone without one, or a ledger without a password, has no '
        'switch', () async {
      final none = startupIn('no-finger');
      await none.setUp(password);
      final without = EncryptedBackupManager(none, vaultOf(none));
      expect(without.canUseFingerprint, isFalse);
      expect(without.fingerprintOn, isFalse);
      none.lock();

      final plain = startupIn('no-password');
      final quiet = Startup(
        LedgerVault(
          plain.directory,
          codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
        ),
        device: DeviceUnlock('phone', _Key()),
      );
      await quiet.setUpWithoutPassword();
      expect(
        EncryptedBackupManager(quiet, vaultOf(quiet)).canUseFingerprint,
        isFalse,
      );
      quiet.lock();
    });
  });
}

/// Stands in for an Android Keystore key behind the fingerprint.
final class _Key implements DeviceKeyWrapper {
  final _secrets = <String, List<int>>{};

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) async {
    final handle = 'blob-${_secrets.length}';
    _secrets[handle] = List.of(secret);
    return handle.codeUnits;
  }

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) async {
    final secret = _secrets[String.fromCharCodes(wrapped)];
    if (secret == null) throw StateError('not this device');
    return secret;
  }
}
