import 'dart:io';

import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/backup/model/phone_backup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_folder.dart';

void main() {
  late Directory directory;
  late FakeFolder folder;
  late Preferences preferences;
  late DateTime now;
  var revision = 1;
  var ledger = 'ledger-one';

  setUp(() {
    directory = Directory.systemTemp.createTempSync('phone-backup-');
    folder = FakeFolder();
    preferences = Preferences();
    now = DateTime(2026, 10, 27, 9);
    revision = 1;
    ledger = 'ledger-one';
  });
  tearDown(() => directory.deleteSync(recursive: true));

  PhoneBackup backup() => PhoneBackup(
    folder,
    preferences,
    withBackup: (use) async {
      final file = File('${directory.path}/backup.etbk')
        ..writeAsStringSync('backup $revision');
      await use(file);
    },
    revision: () => revision,
    ledger: ledger,
    clock: () => now,
  );

  test('choosing a folder writes the first backup into it', () async {
    final phone = backup();
    expect(await phone.choose(), isTrue);
    expect(phone.on, isTrue);
    expect(phone.folderName, '備份');
    expect(folder.files.keys, [phone.nameAt(now)]);
    expect(phone.backedUp, now);
  });

  test('a cancelled chooser changes nothing', () async {
    folder.picks = false;
    final phone = backup();
    expect(await phone.choose(), isFalse);
    expect(phone.on, isFalse);
    expect(folder.files, isEmpty);
  });

  test(
    'a folder Android will not keep is said so and nothing is set',
    () async {
      folder.rejects = true;
      final phone = backup();
      await expectLater(phone.choose(), throwsA(isA<FolderRejected>()));
      expect(phone.on, isFalse);
      expect(folder.files, isEmpty);
    },
  );

  test('a backup comes weekly, or daily, and only after a change', () async {
    final phone = backup();
    await phone.choose();
    now = now.add(const Duration(days: 2));
    revision = 2;
    expect(await phone.backUpIfDue(), isFalse, reason: 'not a week yet');
    phone.setDaily(true);
    expect(await phone.backUpIfDue(), isTrue);
    now = now.add(const Duration(days: 2));
    expect(await phone.backUpIfDue(), isFalse, reason: 'nothing changed');
  });

  test('the newest five of its own are kept; other files are left', () async {
    folder.files['相片.jpg'] = 'mine';
    // Another ledger's backup, such as the one before a restore.
    folder.files['記帳本-other-20260101-0900.etbk'] = 'other';
    final phone = backup();
    await phone.choose();
    phone.setDaily(true);
    for (var day = 1; day <= 6; day++) {
      now = now.add(const Duration(days: 1));
      revision++;
      await phone.backUpIfDue();
    }
    final ours =
        folder.files.keys.where((n) => n.startsWith('記帳本-ledger-')).toList()
          ..sort();
    expect(ours, hasLength(PhoneBackup.keep));
    expect(ours.last, phone.nameAt(now));
    expect(folder.files['相片.jpg'], 'mine');
    expect(folder.files['記帳本-other-20260101-0900.etbk'], 'other');
  });

  test('a folder no longer allowed is a problem, not a crash', () async {
    final phone = backup();
    await phone.choose();
    folder.allowedNow = false;
    now = now.add(const Duration(days: 8));
    revision = 2;
    expect(await phone.backUpIfDue(), isFalse);
    expect(phone.problem, isNotNull);
    expect(phone.busy, isFalse);
  });

  test('stopping gives the folder back and keeps its backups', () async {
    final phone = backup();
    await phone.choose();
    await phone.stop();
    expect(phone.on, isFalse);
    expect(folder.allowedNow, isFalse);
    expect(folder.files, hasLength(1));
  });

  test('the backups written before a reset of the keys are found by the '
      'time in their names, in its minute by when they were written, and '
      'deleted only when asked (review 22 finding 2)', () async {
    folder.files['相片.jpg'] = 'mine';
    folder.files['記帳本-other-20260101-0900.etbk'] = 'other';
    final phone = backup();
    await phone.choose(); // 2026-10-27 09:00
    now = DateTime(2026, 10, 28, 10, 30);
    revision = 2;
    await phone.backUpNow();
    final first = phone.nameAt(DateTime(2026, 10, 27, 9));
    final second = phone.nameAt(now);
    expect(first, '記帳本-ledger-20261027-0900.etbk');
    expect(second, '記帳本-ledger-20261028-1030.etbk');
    // Reset at 10:30:40, in the minute of the second backup.
    final reset = DateTime(2026, 10, 28, 10, 30, 40);
    folder.modifiedAt[second] = DateTime(2026, 10, 28, 10, 30, 50);
    expect(
      [for (final f in await phone.writtenBefore(reset, epoch: 2)) f.name],
      [first],
    );
    folder.modifiedAt[second] = DateTime(2026, 10, 28, 10, 30, 20);
    final old = await phone.writtenBefore(reset, epoch: 2);
    expect([for (final f in old) f.name], [second, first]);
    // Nothing went until asked.
    expect(folder.files, hasLength(4));
    for (final file in old) {
      await phone.remove(file.id);
    }
    expect(folder.files.keys.toSet(), {
      '相片.jpg',
      '記帳本-other-20260101-0900.etbk',
    });
    // With no folder chosen there is nothing to list.
    await phone.stop();
    expect(await phone.writtenBefore(reset, epoch: 2), isEmpty);
  });
}
