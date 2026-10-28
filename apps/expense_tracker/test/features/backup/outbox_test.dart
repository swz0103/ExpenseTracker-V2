import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/core/preferences.dart';
import 'package:expense_tracker/src/features/backup/model/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late Preferences preferences;
  late List<bool> scheduled;
  var revision = 1;
  var written = 0;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('outbox-');
    preferences = Preferences();
    scheduled = [];
    revision = 1;
    written = 0;
  });
  tearDown(() => directory.deleteSync(recursive: true));

  Outbox outbox({String ledger = 'ledger-one'}) => Outbox(
    directory,
    preferences,
    write: (folder) async {
      folder.createSync(recursive: true);
      written++;
      return File('${folder.path}/記帳本-$written.etbk')
        ..writeAsStringSync('backup $revision');
    },
    revision: () => revision,
    ledger: ledger,
    schedule: ({required on}) async => scheduled.add(on),
    clock: () => DateTime.utc(2026, 10, 28, 9),
  );

  Directory folder() => Outbox.folderOf(directory);
  Map<String, Object?> ready() =>
      jsonDecode(File('${folder().path}/ready.json').readAsStringSync())
          as Map<String, Object?>;
  List<String> backups() => [
    for (final f in folder().listSync())
      if (f.path.endsWith('.etbk')) f.uri.pathSegments.last,
  ];
  void deliver(Map<String, Object?> json) => File(
    '${folder().path}/delivered.json',
  ).writeAsStringSync(jsonEncode(json));

  test('nothing is left, and the job stops, with nowhere to deliver', () async {
    expect(await outbox().prepare(), isFalse);
    expect(scheduled, [false]);
    expect(folder().existsSync(), isFalse);
  });

  test('a changed ledger is left once, the one before replaced', () async {
    preferences.phoneFolderSet('content://tree/backups', name: '備份');
    final box = outbox();
    expect(await box.prepare(), isTrue);
    expect(scheduled, [true]);
    expect(ready(), {
      'v': 1,
      'file': '記帳本-1.etbk',
      'revision': 1,
      'ledger': 'ledger-one',
      'mark': 'ledger',
      'at': DateTime.utc(2026, 10, 28, 9).millisecondsSinceEpoch,
    });
    // Unchanged: not written again.
    expect(await box.prepare(), isFalse);
    revision = 2;
    expect(await box.prepare(), isTrue);
    expect(backups(), ['記帳本-2.etbk']);
    expect(ready()['revision'], 2);
  });

  test('a revision every place already holds is not left', () async {
    preferences
      ..phoneFolderSet('content://tree/backups', name: '備份')
      ..phoneBackup(DateTime.utc(2026, 10, 27), 1)
      ..update(driveLinked: true)
      ..driveBackup(DateTime.utc(2026, 10, 27), 1);
    expect(await outbox().prepare(), isFalse);
    preferences.driveBackup(DateTime.utc(2026, 10, 27), 0);
    expect(await outbox().prepare(), isTrue);
  });

  test('what the job delivered is noted, for this ledger and folder', () async {
    preferences
      ..phoneFolderSet('content://tree/backups', name: '備份')
      ..update(driveLinked: true);
    final box = outbox();
    await box.prepare();
    final at = DateTime.utc(2026, 10, 28, 15);
    deliver({
      'phone': {
        'at': at.millisecondsSinceEpoch,
        'revision': 1,
        'ledger': 'ledger-one',
        'uri': 'content://tree/backups',
      },
      'drive': {
        'at': at.millisecondsSinceEpoch,
        'revision': 1,
        'ledger': 'ledger-one',
      },
      'problems': <String, Object?>{},
    });
    expect(box.collect(), isEmpty);
    expect(preferences.phoneBackedUp, at);
    expect(preferences.phoneRevision, 1);
    expect(preferences.driveBackedUp, at);
    expect(preferences.driveRevision, 1);
  });

  test('another ledger\'s or folder\'s delivery is not this one\'s', () async {
    preferences.phoneFolderSet('content://tree/other', name: '別的');
    final box = outbox();
    final at = DateTime.utc(2026, 10, 28, 15).millisecondsSinceEpoch;
    deliver({
      'phone': {
        'at': at,
        'revision': 1,
        'ledger': 'ledger-one',
        'uri': 'content://tree/backups',
      },
    });
    box.collect();
    expect(preferences.phoneBackedUp, isNull);
    preferences.phoneFolderSet('content://tree/backups', name: '備份');
    expect(outbox(ledger: 'ledger-two').collect(), isEmpty);
    expect(preferences.phoneBackedUp, isNull);
  });

  test('a problem in the background is said once', () async {
    final box = outbox();
    folder().createSync(recursive: true);
    deliver({
      'problems': {
        'drive': {'at': 5, 'message': 'offline'},
      },
    });
    expect(box.collect(), ['雲端硬碟：offline']);
    expect(box.collect(), isEmpty);
    deliver({
      'problems': {
        'drive': {'at': 6, 'message': 'offline'},
      },
    });
    expect(box.collect(), ['雲端硬碟：offline']);
  });
}
