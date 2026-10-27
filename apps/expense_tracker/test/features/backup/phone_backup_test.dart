import 'dart:io';

import 'package:expense_tracker/src/core/preferences.dart';
import 'package:expense_tracker/src/features/backup/model/phone_backup.dart';
import 'package:flutter_test/flutter_test.dart';

/// A folder kept in memory.
final class _Folder implements FolderPort {
  final files = <String, String>{};
  var allowedNow = true;
  var picks = true;

  @override
  Future<({String uri, String name})?> pick() async =>
      picks ? (uri: 'content://tree/backups', name: '備份') : null;

  @override
  Future<bool> allowed(String uri) async => allowedNow;

  @override
  Future<void> forget(String uri) async => allowedNow = false;

  @override
  Future<List<FolderFile>> list(String uri) async => [
    for (final name in files.keys)
      (id: name, name: name, modified: DateTime(2026)),
  ];

  @override
  Future<void> write(String uri, File file, String name) async =>
      files[name] = file.readAsStringSync();

  @override
  Future<void> delete(String uri, String id) async => files.remove(id);
}

void main() {
  late Directory directory;
  late _Folder folder;
  late Preferences preferences;
  late DateTime now;
  var revision = 1;
  var ledger = 'ledger-one';

  setUp(() {
    directory = Directory.systemTemp.createTempSync('phone-backup-');
    folder = _Folder();
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
    final ours = folder.files.keys
        .where((n) => n.startsWith('記帳本-ledger-'))
        .toList()
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
}
