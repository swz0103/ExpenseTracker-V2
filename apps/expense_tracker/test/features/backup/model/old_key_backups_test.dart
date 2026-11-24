import 'dart:io';

import 'package:core/app_core.dart' show FixedClock;
import 'package:core/foundation_values.dart' show UtcInstant;
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:expense_tracker/src/features/backup/model/drive_backup.dart';
import 'package:expense_tracker/src/features/backup/model/encrypted_backup_manager.dart';
import 'package:expense_tracker/src/features/backup/model/old_key_backups.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/time/app_clock.dart';
import 'package:expense_tracker/src/features/backup/model/phone_backup.dart';

import '../../../support/fake_drive.dart';
import '../../../support/fake_folder.dart';

/// D15: after a reset of the keys, the backups still sealed with the old
/// ones are found, on Drive and on the phone, and taken away only when
/// asked.
void main() {
  const password = 'correct horse battery';
  late Directory directory;
  late FakeDrive http;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('old-keys-');
    http = FakeDrive();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  DriveBackup drive() => DriveBackup(
    http,
    token: ({required interactive}) async => 'token',
    forget: (token) async {},
  );

  OpenVault vaultOf(Startup startup) => switch (startup.state) {
    Ready(:final vault) => vault,
    _ => throw StateError('Not open'),
  };

  test('a backup goes up marked with its key epoch', () async {
    final file = File('${directory.path}/記帳本-1.etbk')..writeAsStringSync('one');
    await drive().upload(file, ledger: 'L1', epoch: 2);
    await drive().upload(file, ledger: 'L1');
    expect([for (final f in await drive().list()) f.epoch], [null, '2']);
  });

  test('on Drive: those of earlier epochs and unmarked ones, of this ledger '
      'only; moved to the trash when asked', () async {
    http
      ..seed('a.etbk', ledger: 'L1', epoch: 1)
      ..seed('b.etbk', ledger: 'L1')
      ..seed('c.etbk', ledger: 'L1', epoch: 2)
      ..seed('d.etbk', ledger: 'L2', epoch: 1);
    final client = drive();
    final old = OldKeyBackups(
      epoch: 2,
      localBackups: () async => const [],
      driveFiles: () => client.list(interactive: false, ledger: 'L1'),
      trashOnDrive: client.trash,
    );
    final found = await old.find();
    // Newest first: b, then a.
    expect([for (final f in found.drive) f.name], ['b.etbk', 'a.etbk']);
    expect(found.local, isEmpty);
    expect(found.driveUnreached, isFalse);
    // Nothing goes until asked.
    expect(http.kept.map((f) => f.name).toSet(), {
      'a.etbk',
      'b.etbk',
      'c.etbk',
      'd.etbk',
    });
    expect(await old.remove(found), 2);
    expect(http.kept.map((f) => f.name).toSet(), {'c.etbk', 'd.etbk'});
  });

  test('Drive not answering leaves its list out, and says so', () async {
    final old = OldKeyBackups(
      epoch: 2,
      localBackups: () async => const [],
      driveFiles: () async =>
          throw const DriveException(DriveProblem.offline, 'offline'),
    );
    final found = await old.find();
    expect(found.isEmpty, isTrue);
    expect(found.driveUnreached, isTrue);
  });

  test('on the phone: the backups written before the reset', () async {
    final startup = Startup(
      LedgerVault(
        directory,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      ),
      check: SqlLedgerDataSource.check,
    );
    await startup.setUp(password);
    final before = EncryptedBackupManager(startup, vaultOf(startup));
    expect(before.backupEpoch, 1);
    final oldPath = await before.backUp();
    await startup.resetKeys(password: password);
    final after = EncryptedBackupManager(startup, vaultOf(startup));
    // A reset adds an epoch for the backups to come.
    expect(after.backupEpoch, 2);
    final newPath = await after.backUp();
    final old = OldKeyBackups(
      epoch: after.backupEpoch,
      localBackups: after.keptBackups,
    );
    final found = await old.find();
    expect(found.drive, isEmpty);
    expect([for (final (file, _) in found.local) file.path], [oldPath]);
    expect(await old.remove(found), 1);
    expect(File(oldPath).existsSync(), isFalse);
    expect(File(newPath).existsSync(), isTrue);
    vaultOf(startup).close();
  });

  test('after a reset: the folder\'s backups written before it and the '
      'databases kept beside the ledger are listed, and taken only when '
      'asked (review 22 finding 2)', () async {
    final startup = Startup(
      LedgerVault(
        directory,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      ),
      check: SqlLedgerDataSource.check,
    );
    await startup.setUp(password);
    // A copy set aside as damaged before, still under the old keys.
    final damaged = File(
      '${directory.path}/ledger-damaged-2026-11-01T08-00-00.000Z.db',
    )..writeAsStringSync('old pages');
    final folder = FakeFolder();
    final preferences = Preferences()
      ..phoneFolderSet('content://tree/backups', name: '備份');
    var now = DateTime(2026, 11, 20, 9);
    final phone = PhoneBackup(
      folder,
      preferences,
      withBackup: (use) async {
        final file = File('${directory.path}/b.etbk')..writeAsStringSync('b');
        await use(file);
      },
      revision: () => 1,
      ledger: 'ledger-one',
      clock: () => now,
    );
    await phone.backUpNow();
    final oldName = phone.nameAt(now);
    expect(startup.keysResetAt, isNull);
    final resetAt = DateTime(2026, 11, 24, 10);
    AppClock.use(FixedClock(UtcInstant(resetAt.toUtc())));
    addTearDown(AppClock.reset);
    await startup.resetKeys(password: password);
    expect(startup.keysResetAt, resetAt);
    now = DateTime(2026, 11, 24, 11);
    await phone.backUpNow();
    final newName = phone.nameAt(now);
    final after = EncryptedBackupManager(startup, vaultOf(startup));
    final old = OldKeyBackups(
      epoch: after.backupEpoch,
      localBackups: after.keptBackups,
      folderBackups: () => phone.writtenBefore(
        resetAt,
        epoch: after.backupEpoch,
        head: EncryptedBackupManager.head,
      ),
      deleteInFolder: phone.remove,
      keptDatabases: after.keptDatabases,
      deleteDatabase: after.deleteKeptDatabase,
    );
    final found = await old.find();
    expect([for (final f in found.folder) f.name], [oldName]);
    expect([for (final (f, _) in found.databases) f.path], [damaged.path]);
    expect(found.isEmpty, isFalse);
    expect(folder.files.keys.toSet(), {oldName, newName});
    expect(damaged.existsSync(), isTrue);
    expect(await old.remove(found), 2);
    expect(folder.files.keys, [newName]);
    expect(damaged.existsSync(), isFalse);
    expect(after.keptDatabases(), isEmpty);
    vaultOf(startup).close();
  });

  test('in the folder, the key epoch in a backup\'s header decides, '
      'whatever its name or written time says (review 27 finding 1)', () async {
    final startup = Startup(
      LedgerVault(
        directory,
        codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
      ),
      check: SqlLedgerDataSource.check,
    );
    await startup.setUp(password);
    var manager = EncryptedBackupManager(startup, vaultOf(startup));
    final folder = FakeFolder();
    final preferences = Preferences()
      ..phoneFolderSet('content://tree/backups', name: '備份');
    // The reset and both backups fall in the same minute, 10:00.
    var now = DateTime(2026, 11, 24, 10, 0, 5);
    var revision = 1;
    final phone = PhoneBackup(
      folder,
      preferences,
      withBackup: (use) => manager.withBackup(use, withPhotos: false),
      revision: () => revision++,
      ledger: 'ledger-one',
      clock: () => now,
    );
    await phone.backUpNow();
    final name = phone.nameAt(now);
    expect(name, '記帳本-ledger-20261124-1000.etbk');
    // The old-key backup moved aside under an earlier minute's name, so
    // the new one can take the same minute's name.
    const oldName = '記帳本-ledger-20261124-0959.etbk';
    folder
      ..bytes[oldName] = folder.bytes.remove(name)!
      ..files[oldName] = folder.files.remove(name)!;
    final resetAt = DateTime(2026, 11, 24, 10, 0, 30);
    AppClock.use(FixedClock(UtcInstant(resetAt.toUtc())));
    addTearDown(AppClock.reset);
    await startup.resetKeys(password: password);
    manager = EncryptedBackupManager(startup, vaultOf(startup));
    expect(manager.backupEpoch, 2);
    now = DateTime(2026, 11, 24, 10, 0, 50);
    await phone.backUpNow();
    // The folder gives no written time for either: 1970.
    folder.modifiedAt
      ..[name] = DateTime.fromMillisecondsSinceEpoch(0)
      ..[oldName] = DateTime.fromMillisecondsSinceEpoch(0);
    // A file put there by hand under this minute's name, not a backup:
    // its header cannot be read and its written time is unknown, so it
    // is kept out of the list too.
    folder.files['記帳本-ledger-20261124-1000x.etbk'] = 'not a backup';
    final listed = await phone.writtenBefore(
      resetAt,
      epoch: 2,
      head: EncryptedBackupManager.head,
    );
    expect([for (final f in listed) f.name], [oldName]);
    // Seen from epoch 1, neither backup is sealed before it.
    expect(
      await phone.writtenBefore(
        resetAt,
        epoch: 1,
        head: EncryptedBackupManager.head,
      ),
      isEmpty,
    );
    vaultOf(startup).close();
  });

  test('a backup in the folder whose header cannot be read and whose '
      'written time the folder does not give is kept, in the reset\'s '
      'minute (review 27 finding 1)', () async {
    final folder = FakeFolder();
    final preferences = Preferences()
      ..phoneFolderSet('content://tree/backups', name: '備份');
    final now = DateTime(2026, 11, 24, 10, 0, 50);
    final phone = PhoneBackup(
      folder,
      preferences,
      withBackup: (use) async {
        final file = File('${directory.path}/b.etbk')..writeAsStringSync('b');
        await use(file);
      },
      revision: () => 1,
      ledger: 'ledger-one',
      clock: () => now,
    );
    await phone.backUpNow();
    final name = phone.nameAt(now);
    final resetAt = DateTime(2026, 11, 24, 10, 0, 30);
    folder.modifiedAt[name] = DateTime.fromMillisecondsSinceEpoch(0);
    expect(
      await phone.writtenBefore(
        resetAt,
        epoch: 2,
        head: EncryptedBackupManager.head,
      ),
      isEmpty,
    );
    // With a known time before the reset it is listed.
    folder.modifiedAt[name] = DateTime(2026, 11, 24, 10, 0, 10);
    expect(
      [
        for (final f in await phone.writtenBefore(
          resetAt,
          epoch: 2,
          head: EncryptedBackupManager.head,
        ))
          f.name,
      ],
      [name],
    );
  });

  test(
    'a folder that cannot be read leaves its list out, and says so',
    () async {
      final old = OldKeyBackups(
        epoch: 2,
        localBackups: () async => const [],
        folderBackups: () async => throw StateError('no permission'),
      );
      final found = await old.find();
      expect(found.isEmpty, isTrue);
      expect(found.folderUnreached, isTrue);
    },
  );
}
