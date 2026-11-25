import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/platform/memory_keystore.dart';
import 'package:expense_tracker/src/features/reminders/model/reminder_alerts.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/platform/quick_action.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/src/features/reminders/ui/reminders_section.dart'
    show reminderBookOf;
import 'package:vault/backup_security.dart' show DeviceKeyWrapper;

/// A Keystore that refuses to seal, as one that fails on a phone.
final class _Refusing implements DeviceKeyWrapper {
  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) async =>
      throw StateError('keystore');

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) async =>
      throw StateError('keystore');
}

/// The Keystore of this run, counting what it is asked to seal.
final class _Counting implements DeviceKeyWrapper {
  var wraps = 0;

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) {
    wraps++;
    return MemoryKeystore.instance.wrap(secret, context);
  }

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) =>
      MemoryKeystore.instance.unwrap(wrapped, context);
}

/// The Keystore of this run, refusing to open the next [refusals] times,
/// as a busy one at the start.
final class _Flaky implements DeviceKeyWrapper {
  var refusals = 0;

  @override
  Future<List<int>> wrap(List<int> secret, List<int> context) =>
      MemoryKeystore.instance.wrap(secret, context);

  @override
  Future<List<int>> unwrap(List<int> wrapped, List<int> context) async {
    if (refusals > 0) {
      refusals--;
      throw StateError('keystore busy');
    }
    return MemoryKeystore.instance.unwrap(wrapped, context);
  }
}

void main() {
  late Directory directory;
  late File file;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('preferences-');
    file = File('${directory.path}/preferences.json');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  /// The preferences in [file], as the app opens them at its start.
  /// Whatever opening writes is written before it is used.
  Future<Preferences> open() async {
    final preferences = await Preferences.open(file);
    await preferences.saved;
    return preferences;
  }

  /// Makes [change] to the preferences in [file], and waits until it is
  /// written.
  Future<void> change(void Function(Preferences preferences) change) async {
    final preferences = await open();
    change(preferences);
    await preferences.saved;
  }

  Map<String, Object?> plain() =>
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

  File sibling(String name) => File('${directory.path}/$name');

  test('a settings file that cannot be read or written is kept in the error '
      'log; the defaults and this run go on', () async {
    file.writeAsStringSync('not json');
    var before = ErrorLog.instance.count;
    final read = await open();
    expect(read.appearance, Appearance.system);
    expect(ErrorLog.instance.count, before + 1);
    expect(ErrorLog.instance.entries.first.$2, startsWith('讀取設定：'));

    // Where its folder should be there is a file: nothing can be written.
    // The change is kept for this run, and the fault for 診斷.
    File('${directory.path}/blocked').writeAsStringSync('x');
    // Kept once: the same fault again is counted on it.
    before = ErrorLog.instance.count;
    final unwritable = await Preferences.open(
      File('${directory.path}/blocked/preferences.json'),
    );
    unwritable.update(appearance: Appearance.dark);
    await unwritable.saved;
    expect(unwritable.appearance, Appearance.dark);
    expect(ErrorLog.instance.count, before + 1);
    expect(
      ErrorLog.instance.entries.first.$2,
      startsWith('儲存設定：FileSystemException: '),
    );
  });

  test('preferences are kept in their file and read back', () async {
    await change(
      (p) => p.update(
        appearance: Appearance.dark,
        vibration: Vibration.light,
        dailyNudge: true,
        nudgeHour: 22,
        nudgeMinute: 45,
        exactReminders: true,
        phoneDaily: true,
      ),
    );
    await change((p) => p.phoneFolderSet('content://tree/backups', name: '備份'));
    final again = await open();
    expect(again.nudgeMinute, 45);
    expect(again.exactReminders, isTrue);
    expect(again.phoneDaily, isTrue);
    expect(
      (again.phoneFolder, again.phoneFolderName),
      ('content://tree/backups', '備份'),
    );
    expect(again.appearance, Appearance.dark);
    expect(again.vibration, Vibration.light);
    expect(again.dueAlerts, isFalse);
    expect(again.dailyNudge, isTrue);
    expect(again.nudgeHour, 22);
  });

  test(
    "the broker's discount is 6折 until set, kept, and held to 0.01%-100%",
    () async {
      expect((await open()).brokerDiscount, 6000);
      await change((p) => p.update(brokerDiscount: 2800));
      expect((await open()).brokerDiscount, 2800);
      final preferences = await open()
        ..update(brokerDiscount: 0);
      expect(preferences.brokerDiscount, 1);
      preferences.update(brokerDiscount: 12000);
      expect(preferences.brokerDiscount, 10000);
      await preferences.saved;
      // A file written before the setting existed reads as 6折.
      file.writeAsStringSync('{"appearance": "dark"}');
      expect((await open()).brokerDiscount, 6000);
    },
  );

  test('backups with photos wait for Wi-Fi until the person says otherwise '
      '(AND-05)', () async {
    expect((await open()).photosOnWifi, isTrue);
    await change((p) => p.update(photosOnWifi: false));
    expect((await open()).photosOnWifi, isFalse);
    expect(plain()['photosOnWifi'], isFalse);
    file.writeAsStringSync('{"drivePhotos": true}');
    expect((await open()).photosOnWifi, isTrue);
  });

  test('自動上鎖 is 5 分鐘 until chosen, and the choice is kept (SEC-07)', () async {
    expect((await open()).autoLock, AutoLock.fiveMinutes);
    var told = 0;
    final preferences = await open();
    preferences.watch(const {PreferenceTopic.lock}).addListener(() => told++);
    preferences.update(autoLock: AutoLock.immediately);
    expect(told, 1);
    await preferences.saved;
    expect((await open()).autoLock, AutoLock.immediately);
    // Another setting changed leaves it as chosen, and tells it nothing.
    preferences.update(dailyNudge: true);
    expect(told, 1);
    await preferences.saved;
    expect((await open()).autoLock, AutoLock.immediately);
    // A file written before the setting existed, or naming a choice this
    // version does not have, reads as 5 分鐘.
    file.writeAsStringSync('{"appearance": "dark"}');
    expect((await open()).autoLock, AutoLock.fiveMinutes);
    file.writeAsStringSync('{"autoLock": "tenSeconds"}');
    expect((await open()).autoLock, AutoLock.fiveMinutes);
  });

  test('the auto-lock choices: their words and how long away locks', () {
    expect(
      [for (final a in AutoLock.values) (a.label, a.after)],
      const [
        ('立即', Duration.zero),
        ('1 分鐘', Duration(minutes: 1)),
        ('5 分鐘', Duration(minutes: 5)),
        ('15 分鐘', Duration(minutes: 15)),
        ('不自動上鎖', null),
      ],
    );
    expect(AutoLock.standard, AutoLock.fiveMinutes);
  });

  test('a trip the app itself started locks no sooner than five minutes, '
      'and a longer choice or never is left as it is', () {
    Duration? limit(AutoLock a, {required bool onErrand}) =>
        a.limit(onErrand: onErrand);
    expect(limit(AutoLock.immediately, onErrand: false), Duration.zero);
    expect(
      limit(AutoLock.immediately, onErrand: true),
      const Duration(minutes: 5),
    );
    expect(
      limit(AutoLock.oneMinute, onErrand: true),
      const Duration(minutes: 5),
    );
    expect(
      limit(AutoLock.oneMinute, onErrand: false),
      const Duration(minutes: 1),
    );
    expect(
      limit(AutoLock.fiveMinutes, onErrand: true),
      const Duration(minutes: 5),
    );
    expect(
      limit(AutoLock.fifteenMinutes, onErrand: true),
      const Duration(minutes: 15),
    );
    expect(limit(AutoLock.never, onErrand: true), isNull);
    expect(limit(AutoLock.never, onErrand: false), isNull);
  });

  test('a save leaves one whole file behind', () async {
    final preferences = await open()
      ..update(vibration: Vibration.off);
    preferences.driveBackup(DateTime.utc(2026, 10, 27), 4);
    await preferences.saved;
    expect(directory.listSync().where((f) => f.path.endsWith('.new')), isEmpty);
    // One a stop part way left is cleared when the file is next opened.
    final left = File('${file.path}.12345.new')..writeAsStringSync('{');
    await open();
    expect(left.existsSync(), isFalse);
    final again = await open();
    expect(again.vibration, Vibration.off);
    expect(again.driveRevision, 4);
  });

  test('one field of the wrong kind costs only itself', () async {
    // As a file from an older version, or one partly damaged: the Drive
    // stays linked though another setting cannot be read.
    file.writeAsStringSync(
      '{"driveLinked":true,"haptics":"yes","nudgeHour":21.0,'
      '"nudgeMinute":"30","overview":["flow",3,"daily"],'
      '"phoneFolder":"content://tree/backups"}',
    );
    final read = await open();
    expect(read.driveLinked, isTrue);
    expect(
      read.vibration,
      Vibration.standard,
      reason: 'not a yes or no: the default',
    );
    expect(read.nudgeHour, 21);
    expect(read.nudgeMinute, 0, reason: 'not a number: the default');
    expect(read.overview, ['flow', 'daily']);
    expect(read.phoneFolder, 'content://tree/backups');
  });

  test('震動 kept as on or off before 0.20.0 reads as 標準 or 關', () async {
    file.writeAsStringSync('{"haptics":false}');
    expect((await open()).vibration, Vibration.off);
    file.writeAsStringSync('{"haptics":true}');
    expect((await open()).vibration, Vibration.standard);
  });

  test('a broken file leaves the defaults', () async {
    file.writeAsStringSync('{not json');
    final preferences = await open();
    expect(preferences.appearance, Appearance.system);
    expect(preferences.vibration, Vibration.standard);
  });

  group('PRIV-1: what could name the person is sealed', () {
    const folder =
        'content://com.android.externalstorage.documents/tree/'
        'primary%3ADocuments%2F王小明';

    test('the account, the folder and the budgets told of are never in the '
        'plain file, and come back from the sealed part', () async {
      await change((p) {
        p
          ..driveAccountIs('alice@example.com')
          ..phoneFolderSet(folder, name: '王小明')
          ..budgetAlertedSet({'2026-10|餐飲|80'});
      });
      final written = file.readAsStringSync();
      for (final secret in ['alice', 'example', '王小明', 'Documents', '餐飲']) {
        expect(written, isNot(contains(secret)), reason: secret);
      }
      expect(plain().keys, isNot(contains('driveAccount')));
      final sealed = sibling('preferences.sealed').readAsStringSync();
      expect(sealed, isNot(contains('alice')));
      final again = await open();
      expect(again.driveAccount, 'alice@example.com');
      expect((again.phoneFolder, again.phoneFolderName), (folder, '王小明'));
      expect(again.budgetAlerted, {'2026-10|餐飲|80'});
    });

    test("a file an older version wrote is sealed when it is opened", () async {
      file.writeAsStringSync(
        jsonEncode({
          'appearance': 'dark',
          'driveAccount': 'alice@example.com',
          'phoneFolder': folder,
          'phoneFolderName': '王小明',
          'budgetAlerted': ['2026-10|餐飲|80'],
        }),
      );
      final opened = await open();
      await opened.saved;
      expect(file.readAsStringSync(), isNot(contains('alice')));
      expect(file.readAsStringSync(), isNot(contains('王小明')));
      expect(plain()['appearance'], 'dark');
      // It was given an id that says nothing of it.
      final id = opened.phoneFolderId;
      expect(id, isNotNull);
      expect(id, isNot(contains('Documents')));
      final again = await open();
      expect(again.driveAccount, 'alice@example.com');
      expect(again.phoneFolder, folder);
      expect(again.phoneFolderId, id);
      expect(again.budgetAlerted, {'2026-10|餐飲|80'});
    });

    test('a Keystore that will not seal keeps them as before rather than '
        'losing them', () async {
      final preferences = await Preferences.open(file, keystore: _Refusing())
        ..phoneFolderSet(folder, name: '王小明');
      final before = ErrorLog.instance.count;
      await preferences.saved;
      expect(ErrorLog.instance.count, greaterThan(before));
      expect(plain()['phoneFolder'], folder);
      expect(sibling('preferences.sealed').existsSync(), isFalse);
    });

    test('a sealed part that no longer opens leaves the folder to choose '
        'again, and says so', () async {
      await change((p) => p.phoneFolderSet(folder, name: '王小明'));
      sibling('preferences.sealed').writeAsStringSync('memory:gone');
      final before = ErrorLog.instance.count;
      final again = await open();
      expect(again.phoneFolder, isNull);
      expect(ErrorLog.instance.count, before + 1);
      expect(ErrorLog.instance.entries.first.$2, startsWith('讀取設定：'));
      // Kept as it is, for a Keystore that failed only once, until a
      // folder is chosen again.
      again.update(appearance: Appearance.dark);
      await again.saved;
      expect(sibling('preferences.sealed').readAsStringSync(), 'memory:gone');
      again.phoneFolderSet(folder, name: '王小明');
      await again.saved;
      expect(
        sibling('preferences.sealed').readAsStringSync(),
        isNot('memory:gone'),
      );
    });

    test(
      'R34: a Keystore that refuses once at the start is asked again',
      () async {
        final keystore = _Flaky();
        final first = await Preferences.open(file, keystore: keystore)
          ..driveAccountIs('alice@example.com');
        await first.saved;
        keystore.refusals = 1;
        final again = await Preferences.open(file, keystore: keystore);
        expect(again.driveAccount, 'alice@example.com');
      },
    );

    test('R34: what is cleared while the sealed part did not open stays '
        'cleared at the next start', () async {
      final keystore = _Flaky();
      final first = await Preferences.open(file, keystore: keystore)
        ..driveAccountIs('alice@example.com')
        ..phoneFolderSet(folder, name: '王小明');
      await first.saved;
      // Both tries at the start refused: nothing private reads.
      keystore.refusals = 2;
      final unread = await Preferences.open(file, keystore: keystore);
      expect((unread.driveAccount, unread.phoneFolder), (null, null));
      unread
        ..driveAccountIs(null)
        ..phoneFolderSet(null);
      await unread.saved;
      expect(sibling('preferences.sealed').existsSync(), isFalse);
      final later = await Preferences.open(file, keystore: keystore);
      expect((later.driveAccount, later.phoneFolder), (null, null));
    });

    test('R34: a budget notice noted while unread leaves the sealed part '
        'for the next start', () async {
      final keystore = _Flaky();
      final first = await Preferences.open(file, keystore: keystore)
        ..driveAccountIs('alice@example.com');
      await first.saved;
      final kept = sibling('preferences.sealed').readAsStringSync();
      keystore.refusals = 2;
      final unread = await Preferences.open(file, keystore: keystore)
        ..budgetAlertedSet({'2026-10|b1|80'});
      await unread.saved;
      expect(sibling('preferences.sealed').readAsStringSync(), kept);
      final later = await Preferences.open(file, keystore: keystore);
      expect(later.driveAccount, 'alice@example.com');
    });

    test('R34: one value cleared while unread writes the sealed part over '
        'with what is chosen now', () async {
      final keystore = _Flaky();
      final first = await Preferences.open(file, keystore: keystore)
        ..driveAccountIs('alice@example.com')
        ..phoneFolderSet(folder, name: '王小明');
      await first.saved;
      keystore.refusals = 2;
      final unread = await Preferences.open(file, keystore: keystore)
        ..phoneFolderSet(null)
        ..driveAccountIs('bob@example.com');
      await unread.saved;
      final later = await Preferences.open(file, keystore: keystore);
      expect(
        (later.driveAccount, later.phoneFolder),
        ('bob@example.com', null),
      );
    });

    test('nothing private kept: no sealed part, and none asked of the '
        'Keystore', () async {
      final keystore = _Counting();
      final preferences = await Preferences.open(file, keystore: keystore)
        ..update(appearance: Appearance.dark);
      await preferences.saved;
      expect(sibling('preferences.sealed').existsSync(), isFalse);
      expect(keystore.wraps, 0);
      preferences.driveAccountIs('alice@example.com');
      await preferences.saved;
      expect(sibling('preferences.sealed').existsSync(), isTrue);
      preferences.driveAccountIs(null);
      await preferences.saved;
      expect(sibling('preferences.sealed').existsSync(), isFalse);
    });

    test('R37: the notices\' salt is made once, at its first use, kept '
        'sealed and never plain', () async {
      final keystore = _Counting();
      final preferences = await Preferences.open(file, keystore: keystore);
      await preferences.saved;
      // Not made before it is asked for.
      expect(sibling('preferences.sealed').existsSync(), isFalse);
      final salt = preferences.noticeSalt;
      expect(preferences.noticeSalt, salt);
      await preferences.saved;
      expect(sibling('preferences.sealed').existsSync(), isTrue);
      expect(file.readAsStringSync(), isNot(contains(salt.value)));
      expect(plain().keys, isNot(contains('noticeSalt')));
      final again = await Preferences.open(file, keystore: keystore);
      expect(again.noticeSalt, salt);
      // Another install has its own.
      expect(Preferences().noticeSalt, isNot(salt));
    });

    test('review 37: a Keystore that never seals keeps the salt plain, as '
        'the other private fields, the same at every start', () async {
      final preferences = await Preferences.open(file, keystore: _Refusing());
      final salt = preferences.noticeSalt;
      await preferences.saved;
      expect(plain()['noticeSalt'], salt.value);
      expect(sibling('preferences.sealed').existsSync(), isFalse);
      // Opened again and again, as the app at each start: the budgets'
      // notices keep their tags, so none is taken away and posted anew.
      for (var start = 0; start < 3; start++) {
        final again = await Preferences.open(file, keystore: _Refusing());
        expect(again.noticeSalt, salt, reason: 'start $start');
        await again.saved;
      }
    });

    test('review 37: a salt kept plain is sealed, and leaves the plain '
        'file, once the Keystore seals', () async {
      final refused = await Preferences.open(file, keystore: _Refusing());
      final salt = refused.noticeSalt;
      await refused.saved;
      final sealing = await Preferences.open(file, keystore: _Counting());
      await sealing.saved;
      expect(sealing.noticeSalt, salt);
      expect(plain().keys, isNot(contains('noticeSalt')));
      expect(file.readAsStringSync(), isNot(contains(salt.value)));
      expect(sibling('preferences.sealed').existsSync(), isTrue);
      final later = await Preferences.open(file, keystore: _Counting());
      expect(later.noticeSalt, salt);
    });

    test('review 37: a salt made while the sealed part did not open is kept '
        'plain beside it, the same at the next start', () async {
      final keystore = _Flaky();
      final first = await Preferences.open(file, keystore: keystore)
        ..driveAccountIs('alice@example.com');
      await first.saved;
      final kept = sibling('preferences.sealed').readAsStringSync();
      keystore.refusals = 2;
      final unread = await Preferences.open(file, keystore: keystore);
      final salt = unread.noticeSalt;
      await unread.saved;
      // The sealed part stays for a Keystore that failed only this once.
      expect(sibling('preferences.sealed').readAsStringSync(), kept);
      expect(plain()['noticeSalt'], salt.value);
      keystore.refusals = 2;
      final still = await Preferences.open(file, keystore: keystore);
      expect(still.noticeSalt, salt);
    });

    test('a folder chosen gets a new id; the same one again keeps it', () {
      final preferences = Preferences()..phoneFolderSet(folder, name: 'a');
      final first = preferences.phoneFolderId;
      expect(first, isNotNull);
      preferences.phoneFolderSet(folder, name: 'a');
      expect(preferences.phoneFolderId, first);
      preferences.phoneFolderSet('content://tree/other', name: 'b');
      expect(preferences.phoneFolderId, isNot(first));
      preferences.phoneFolderSet(null);
      expect(preferences.phoneFolderId, isNull);
    });
  });

  group('the background jobs are handed what they need, and no more', () {
    test(
      'Drive and the folder, the folder sealed, times in milliseconds',
      () async {
        await change((p) {
          p
            ..update(driveLinked: true, photosOnWifi: false, phoneDaily: true)
            ..driveBackup(DateTime.utc(2026, 10, 28, 3, 4, 5, 123), 7)
            ..phoneFolderSet('content://tree/backups', name: '備份')
            ..phoneBackup(DateTime.utc(2026, 10, 28, 3, 4, 5, 123), 6)
            ..driveAccountIs('alice@example.com');
        });
        final text = sibling('background.json').readAsStringSync();
        for (final secret in ['alice', 'content://', '備份']) {
          expect(text, isNot(contains(secret)), reason: secret);
        }
        final handed = jsonDecode(text) as Map<String, Object?>;
        final phone = handed['phone']! as Map<String, Object?>;
        final preferences = await open();
        // 2026-10-28T03:04:05.123Z is 1,793,156,645,123 ms after 1970.
        expect(handed, {
          'v': 1,
          'updateChecks': true,
          'drive': {'photosOnWifi': false, 'at': 1793156645123, 'revision': 7},
          'phone': {
            'folder': phone['folder'],
            'id': preferences.phoneFolderId,
            'daily': true,
            'at': 1793156645123,
            'revision': 6,
          },
        });
        // The folder opens for the job's use only.
        final sealed = base64.decode(phone['folder']! as String);
        expect(
          utf8.decode(
            await MemoryKeystore.instance.unwrap(
              sealed,
              utf8.encode(Preferences.folderContext),
            ),
          ),
          'content://tree/backups',
        );
        await expectLater(
          MemoryKeystore.instance.unwrap(sealed, utf8.encode('other')),
          throwsStateError,
        );
      },
    );

    test('unlinked and no folder: nothing of either; the update checks as '
        'chosen', () async {
      await change((p) => p.update(updateChecks: false));
      expect(jsonDecode(sibling('background.json').readAsStringSync()), {
        'v': 1,
        'updateChecks': false,
        'drive': null,
        'phone': null,
      });
    });

    test('a file already opened is handed over once, then only when it '
        'changes', () async {
      final preferences = await open();
      await preferences.saved;
      final handed = sibling('background.json');
      expect(handed.existsSync(), isTrue);
      handed.deleteSync();
      // A choice the jobs do not read writes nothing for them.
      preferences.update(appearance: Appearance.dark);
      await preferences.saved;
      expect(handed.existsSync(), isFalse);
      preferences.update(updateChecks: false);
      await preferences.saved;
      expect(handed.existsSync(), isTrue);
    });
  });

  group('3.3b: kept off the UI thread, in one write for changes together', () {
    test('changes made together are written once, the last of each', () async {
      final keystore = _Counting();
      final preferences = await Preferences.open(file, keystore: keystore);
      await preferences.saved;
      for (var i = 0; i < 20; i++) {
        preferences
          ..driveAccountIs('a$i@example.com')
          ..update(nudgeHour: i);
      }
      // Nothing is written before the caller's turn ends.
      expect(file.existsSync() && plain()['nudgeHour'] == 19, isFalse);
      await preferences.saved;
      expect(keystore.wraps, 1);
      expect(plain()['nudgeHour'], 19);
      expect((await open()).driveAccount, 'a19@example.com');
    });

    test('a change while a write is under way is written after it', () async {
      final preferences = await open();
      await preferences.saved;
      preferences.update(nudgeHour: 5);
      final first = preferences.saved;
      await Future<void>.delayed(Duration.zero);
      preferences.update(nudgeHour: 6);
      await first;
      await preferences.saved;
      expect(plain()['nudgeHour'], 6);
    });
  });

  group('3.3b: a change tells only the part it is in', () {
    late Preferences preferences;
    late Map<PreferenceTopic, int> told;
    setUp(() {
      preferences = Preferences();
      told = {for (final t in PreferenceTopic.values) t: 0};
      for (final topic in PreferenceTopic.values) {
        preferences
            .watch({topic})
            .addListener(() => told[topic] = told[topic]! + 1);
      }
    });

    Map<PreferenceTopic, int> heard() => {
      for (final MapEntry(:key, :value) in told.entries)
        if (value > 0) key: value,
    };

    test('a backup noted in the background plans no reminders and writes '
        'no widget', () {
      preferences.driveBackup(DateTime.utc(2026, 11, 1), 3);
      expect(heard(), {PreferenceTopic.driveBackup: 1});
      preferences.phoneBackup(DateTime.utc(2026, 11, 1), 3);
      expect(heard(), {
        PreferenceTopic.driveBackup: 1,
        PreferenceTopic.phoneBackup: 1,
      });
    });

    test('each setting tells its own part', () {
      preferences.update(appearance: Appearance.dark);
      preferences.update(dailyNudge: true);
      preferences.update(widgetFigures: WidgetFigures.amounts);
      preferences.update(updateChecks: false);
      preferences.overviewSet(['flow']);
      preferences.update(autoLock: AutoLock.never);
      preferences.update(brokerDiscount: 2800);
      preferences.update(started: true);
      expect(heard(), {
        PreferenceTopic.look: 1,
        PreferenceTopic.reminders: 1,
        PreferenceTopic.homeWidget: 1,
        PreferenceTopic.updates: 1,
        PreferenceTopic.overview: 1,
        PreferenceTopic.lock: 1,
        PreferenceTopic.trading: 1,
        PreferenceTopic.start: 1,
      });
    });

    test('nothing changed, or kept for the app alone, tells no one', () {
      preferences.update(appearance: Appearance.system);
      preferences.overviewSet(null);
      preferences.budgetAlertedSet({'2026-11|餐飲|80'});
      preferences.updateChecked(DateTime.utc(2026, 11, 1));
      preferences.updateLater(skip: 3);
      expect(heard(), isEmpty);
    });

    test('the same order of blocks set again tells no one', () {
      preferences.overviewSet(['flow', 'daily']);
      preferences.overviewSet(['flow', 'daily']);
      expect(told[PreferenceTopic.overview], 1);
    });
  });
  test('the palette turns dark and back when painted', () {
    addTearDown(() => Shade.dark = false);
    const ink = AppColors.ink;
    expect(ink.toARGB32(), 0xFF26323A);
    Shade.dark = true;
    expect(ink.toARGB32(), 0xFFCDD4D7);
    expect(AppColors.paper.computeLuminance(), lessThan(0.05));
    expect(AppColors.onAccent.toARGB32(), 0xFF0F1A1F);
    Shade.dark = false;
    expect(AppColors.paper.computeLuminance(), greaterThan(0.8));
  });

  test('words read at 4.5:1 or more on every surface, light and dark', () {
    addTearDown(() => Shade.dark = false);
    double contrast(Color a, Color b) {
      final (x, y) = (a.computeLuminance(), b.computeLuminance());
      return (max(x, y) + 0.05) / (min(x, y) + 0.05);
    }

    const words = {
      'ink': AppColors.ink,
      'muted': AppColors.muted,
      'hint': AppColors.hint,
      'accent': AppColors.accent,
      'positive': AppColors.positive,
      'negative': AppColors.negative,
      'investment': AppColors.investment,
      'goldText': AppColors.goldText,
      'transfer': AppColors.transfer,
      'receivable': AppColors.receivable,
    };
    const surfaces = {
      'paper': AppColors.paper,
      'panel': AppColors.panel,
      'tile': AppColors.tile,
      'hero': AppColors.hero,
      'selected': AppColors.selected,
    };
    for (final dark in [false, true]) {
      Shade.dark = dark;
      for (final MapEntry(key: w, value: word) in words.entries) {
        for (final MapEntry(key: s, value: surface) in surfaces.entries) {
          expect(
            contrast(word, surface),
            greaterThanOrEqualTo(4.5),
            reason: '$w on $s, ${dark ? 'dark' : 'light'}',
          );
        }
      }
      for (final fill in [
        AppColors.accent,
        AppColors.positive,
        AppColors.negative,
      ]) {
        expect(contrast(AppColors.onAccent, fill), greaterThanOrEqualTo(4.5));
      }
    }
  });

  group('notifications', () {
    final ledger = demoLedger();
    final morning = DateTime(2026, 10, 4, 8);

    test('none unless asked for', () {
      expect(
        alertsFor(reminderBookOf(ledger), Preferences(), morning),
        isEmpty,
      );
    });

    test('due dates at nine, card payments two days early as well', () {
      final preferences = Preferences()..update(dueAlerts: true);
      final alerts = alertsFor(reminderBookOf(ledger), preferences, morning);
      expect(alerts, isNotEmpty);
      expect(alerts.every((a) => a.at.hour == 9), isTrue);
      expect(alerts.every((a) => a.at.isAfter(morning)), isTrue);
      final netflix = alerts.firstWhere((a) => a.title.contains('Netflix'));
      expect((netflix.at.month, netflix.at.day), (10, 5));
      final cards = alerts.where((a) => a.title.startsWith('繳卡費')).length;
      expect(
        alerts.where((a) => a.title.startsWith('2 天後 繳卡費')).length,
        lessThanOrEqualTo(cards),
      );
      final times = [for (final a in alerts) a.at];
      expect(times, [...times]..sort());
    });

    test('the nudge skips today once something is recorded', () {
      final preferences = Preferences()..update(dailyNudge: true);
      final alerts = alertsFor(reminderBookOf(ledger), preferences, morning);
      // The demo book has entries on its today, 10/4.
      expect(alerts.first.at, DateTime(2026, 10, 5, 21));
      // The 62 days of the plan less today.
      expect(alerts, hasLength(61));
      expect(alerts.every((a) => a.quick == QuickAction.expense), isTrue);
      expect(alerts.every((a) => a.tag == nudgeTag), isTrue);
    });

    test('the nudge comes on the minute chosen', () {
      final preferences = Preferences()
        ..update(dailyNudge: true, nudgeHour: 20, nudgeMinute: 30);
      expect(
        alertsFor(reminderBookOf(ledger), preferences, morning).first.at.minute,
        30,
      );
    });

    test('a nudge showing is taken away once something is recorded', () {
      final preferences = Preferences()
        ..update(dailyNudge: true, dueAlerts: true);
      // The demo book has entries on its today.
      final wanted = wantedTags(reminderBookOf(ledger), preferences);
      expect(wanted, isNot(contains(nudgeTag)));
      // Due dates, and the demo's budgets already past their mark.
      expect(
        wanted.every(
          (tag) => tag.startsWith('due:') || tag.startsWith('budget:'),
        ),
        isTrue,
      );
      final dueTags = {
        for (final a in alertsFor(reminderBookOf(ledger), preferences, morning))
          if (a.tag.startsWith('due:')) a.tag,
      };
      expect(wanted, containsAll(dueTags));
    });
  });
}
