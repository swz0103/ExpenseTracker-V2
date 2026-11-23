import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/features/reminders/model/reminder_alerts.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/platform/quick_action.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/src/features/reminders/ui/reminders_section.dart'
    show reminderBookOf;

void main() {
  test('a settings file that cannot be read or written is kept in the error '
      'log; the defaults and this run go on', () {
    final directory = Directory.systemTemp.createTempSync('preferences-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/preferences.json')
      ..writeAsStringSync('not json');
    var before = ErrorLog.instance.count;
    final read = Preferences(file: file);
    expect(read.appearance, Appearance.system);
    expect(ErrorLog.instance.count, before + 1);
    expect(ErrorLog.instance.entries.first.$2, startsWith('讀取設定：'));

    // Where its folder should be there is a file: nothing can be written.
    // The change is kept for this run, and the fault for 診斷.
    File('${directory.path}/blocked').writeAsStringSync('x');
    final unwritable = Preferences(
      file: File('${directory.path}/blocked/preferences.json'),
    );
    before = ErrorLog.instance.count;
    unwritable.update(appearance: Appearance.dark);
    expect(unwritable.appearance, Appearance.dark);
    expect(ErrorLog.instance.count, before + 1);
    expect(
      ErrorLog.instance.entries.first.$2,
      startsWith('儲存設定：FileSystemException: '),
    );
  });

  test('preferences are kept in their file and read back', () {
    final directory = Directory.systemTemp.createTempSync('preferences-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/preferences.json');
    Preferences(file: file).update(
      appearance: Appearance.dark,
      vibration: Vibration.light,
      dailyNudge: true,
      nudgeHour: 22,
      nudgeMinute: 45,
      exactReminders: true,
      phoneDaily: true,
    );
    Preferences(file: file)
        .phoneFolderSet('content://tree/backups', name: '備份');
    final again = Preferences(file: file);
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
    () {
      final directory = Directory.systemTemp.createTempSync('preferences-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/preferences.json');
      expect(Preferences(file: file).brokerDiscount, 6000);
      Preferences(file: file).update(brokerDiscount: 2800);
      expect(Preferences(file: file).brokerDiscount, 2800);
      final preferences = Preferences(file: file)..update(brokerDiscount: 0);
      expect(preferences.brokerDiscount, 1);
      preferences.update(brokerDiscount: 12000);
      expect(preferences.brokerDiscount, 10000);
      // A file written before the setting existed reads as 6折.
      file.writeAsStringSync('{"appearance": "dark"}');
      expect(Preferences(file: file).brokerDiscount, 6000);
    },
  );

  test('backups with photos wait for Wi-Fi until the person says otherwise, '
      'kept under the name the background job reads (AND-05)', () {
    final directory = Directory.systemTemp.createTempSync('preferences-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/preferences.json');
    expect(Preferences(file: file).photosOnWifi, isTrue);
    Preferences(file: file).update(photosOnWifi: false);
    expect(Preferences(file: file).photosOnWifi, isFalse);
    // BackupWorker.kt reads this name.
    expect(Preferences.photosOnWifiKey, 'photosOnWifi');
    expect(file.readAsStringSync(), contains('"photosOnWifi":false'));
    file.writeAsStringSync('{"drivePhotos": true}');
    expect(Preferences(file: file).photosOnWifi, isTrue);
  });

  test('自動上鎖 is 5 分鐘 until chosen, and the choice is kept (SEC-07)', () {
    final directory = Directory.systemTemp.createTempSync('preferences-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/preferences.json');
    expect(Preferences(file: file).autoLock, AutoLock.fiveMinutes);
    var told = 0;
    final preferences = Preferences(file: file)..addListener(() => told++);
    preferences.update(autoLock: AutoLock.immediately);
    expect(told, 1);
    expect(Preferences(file: file).autoLock, AutoLock.immediately);
    // Another setting changed leaves it as chosen.
    Preferences(file: file).update(dailyNudge: true);
    expect(Preferences(file: file).autoLock, AutoLock.immediately);
    // A file written before the setting existed, or naming a choice this
    // version does not have, reads as 5 分鐘.
    file.writeAsStringSync('{"appearance": "dark"}');
    expect(Preferences(file: file).autoLock, AutoLock.fiveMinutes);
    file.writeAsStringSync('{"autoLock": "tenSeconds"}');
    expect(Preferences(file: file).autoLock, AutoLock.fiveMinutes);
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

  test('a save leaves one whole file behind', () {
    final directory = Directory.systemTemp.createTempSync('preferences-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/preferences.json');
    final preferences = Preferences(file: file)
      ..update(vibration: Vibration.off);
    preferences.driveBackup(DateTime.utc(2026, 10, 27), 4);
    expect(File('${file.path}.new').existsSync(), isFalse);
    final again = Preferences(file: file);
    expect(again.vibration, Vibration.off);
    expect(again.driveRevision, 4);
  });

  test('one field of the wrong kind costs only itself', () {
    // As a file from an older version, or one partly damaged: the Drive
    // stays linked though another setting cannot be read.
    final directory = Directory.systemTemp.createTempSync('preferences-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/preferences.json')
      ..writeAsStringSync(
        '{"driveLinked":true,"haptics":"yes","nudgeHour":21.0,'
        '"nudgeMinute":"30","overview":["flow",3,"daily"],'
        '"phoneFolder":"content://tree/backups"}',
      );
    final read = Preferences(file: file);
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

  test('震動 kept as on or off before 0.20.0 reads as 標準 or 關', () {
    final directory = Directory.systemTemp.createTempSync('preferences-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/preferences.json');
    file.writeAsStringSync('{"haptics":false}');
    expect(Preferences(file: file).vibration, Vibration.off);
    file.writeAsStringSync('{"haptics":true}');
    expect(Preferences(file: file).vibration, Vibration.standard);
  });

  test('a broken file leaves the defaults', () {
    final directory = Directory.systemTemp.createTempSync('preferences-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/preferences.json')
      ..writeAsStringSync('{not json');
    final preferences = Preferences(file: file);
    expect(preferences.appearance, Appearance.system);
    expect(preferences.vibration, Vibration.standard);
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
