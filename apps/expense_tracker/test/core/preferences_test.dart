import 'dart:io';
import 'dart:math';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/look/theme.dart';
import 'package:expense_tracker/src/features/reminders/model/notifications.dart';
import 'package:expense_tracker/src/core/preferences.dart';
import 'package:expense_tracker/src/core/quick_action.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preferences are kept in their file and read back', () {
    final directory = Directory.systemTemp.createTempSync('preferences-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/preferences.json');
    Preferences(file: file).update(
      appearance: Appearance.dark,
      haptics: false,
      dailyNudge: true,
      nudgeHour: 22,
      nudgeMinute: 45,
      exactReminders: true,
      phoneDaily: true,
    );
    Preferences(file: file).phoneFolderSet('content://tree/backups', name: '備份');
    final again = Preferences(file: file);
    expect(again.nudgeMinute, 45);
    expect(again.exactReminders, isTrue);
    expect(again.phoneDaily, isTrue);
    expect((again.phoneFolder, again.phoneFolderName), (
      'content://tree/backups',
      '備份',
    ));
    expect(again.appearance, Appearance.dark);
    expect(again.haptics, isFalse);
    expect(again.dueAlerts, isFalse);
    expect(again.dailyNudge, isTrue);
    expect(again.nudgeHour, 22);
  });

  test('a save leaves one whole file behind', () {
    final directory = Directory.systemTemp.createTempSync('preferences-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/preferences.json');
    final preferences = Preferences(file: file)..update(haptics: false);
    preferences.driveBackup(DateTime.utc(2026, 10, 27), 4);
    expect(File('${file.path}.new').existsSync(), isFalse);
    final again = Preferences(file: file);
    expect(again.haptics, isFalse);
    expect(again.driveRevision, 4);
  });

  test('a broken file leaves the defaults', () {
    final directory = Directory.systemTemp.createTempSync('preferences-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/preferences.json')
      ..writeAsStringSync('{not json');
    final preferences = Preferences(file: file);
    expect(preferences.appearance, Appearance.system);
    expect(preferences.haptics, isTrue);
  });

  test('the palette turns dark and back when painted', () {
    addTearDown(() => Shade.dark = false);
    const ink = Hue.ink;
    expect(ink.toARGB32(), 0xFF26323A);
    Shade.dark = true;
    expect(ink.toARGB32(), 0xFFE3E8EA);
    expect(Hue.paper.computeLuminance(), lessThan(0.05));
    expect(Hue.onAccent.toARGB32(), 0xFF0F1A1F);
    Shade.dark = false;
    expect(Hue.paper.computeLuminance(), greaterThan(0.8));
  });

  test('words read at 4.5:1 or more on every surface, light and dark', () {
    addTearDown(() => Shade.dark = false);
    double contrast(Color a, Color b) {
      final (x, y) = (a.computeLuminance(), b.computeLuminance());
      return (max(x, y) + 0.05) / (min(x, y) + 0.05);
    }

    const words = {
      'ink': Hue.ink,
      'muted': Hue.muted,
      'hint': Hue.hint,
      'accent': Hue.accent,
      'positive': Hue.positive,
      'negative': Hue.negative,
      'investment': Hue.investment,
      'goldText': Hue.goldText,
      'transfer': Hue.transfer,
      'receivable': Hue.receivable,
    };
    const surfaces = {
      'paper': Hue.paper,
      'panel': Hue.panel,
      'tile': Hue.tile,
      'hero': Hue.hero,
      'selected': Hue.selected,
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
      for (final fill in [Hue.accent, Hue.positive, Hue.negative]) {
        expect(contrast(Hue.onAccent, fill), greaterThanOrEqualTo(4.5));
      }
    }
  });

  group('notifications', () {
    final ledger = demoLedger();
    final morning = DateTime(2026, 10, 4, 8);

    test('none unless asked for', () {
      expect(alertsFor(ledger, Preferences(), morning), isEmpty);
    });

    test('due dates at nine, card payments two days early as well', () {
      final preferences = Preferences()..update(dueAlerts: true);
      final alerts = alertsFor(ledger, preferences, morning);
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
      final alerts = alertsFor(ledger, preferences, morning);
      // The demo book has entries on its today, 10/4.
      expect(alerts.first.at, DateTime(2026, 10, 5, 21));
      expect(alerts, hasLength(6));
      expect(alerts.every((a) => a.quick == QuickAction.expense), isTrue);
      expect(alerts.every((a) => a.tag == nudgeTag), isTrue);
    });

    test('the nudge comes on the minute chosen', () {
      final preferences = Preferences()
        ..update(dailyNudge: true, nudgeHour: 20, nudgeMinute: 30);
      expect(alertsFor(ledger, preferences, morning).first.at.minute, 30);
    });

    test('a nudge showing is taken away once something is recorded', () {
      final preferences = Preferences()
        ..update(dailyNudge: true, dueAlerts: true);
      // The demo book has entries on its today.
      final wanted = wantedTags(ledger, preferences);
      expect(wanted, isNot(contains(nudgeTag)));
      expect(wanted.every((tag) => tag.startsWith('due:')), isTrue);
      final dueTags = {
        for (final a in alertsFor(ledger, preferences, morning))
          if (a.tag.startsWith('due:')) a.tag,
      };
      expect(wanted, containsAll(dueTags));
    });
  });
}
