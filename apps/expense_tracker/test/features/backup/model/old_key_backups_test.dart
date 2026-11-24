import 'dart:io';

import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:expense_tracker/src/features/backup/model/drive_backup.dart';
import 'package:expense_tracker/src/features/backup/model/encrypted_backup_manager.dart';
import 'package:expense_tracker/src/features/backup/model/old_key_backups.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

import '../../../support/fake_drive.dart';

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
}
