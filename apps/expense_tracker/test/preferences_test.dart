import 'dart:io';

import 'package:expense_tracker/src/demo/seed.dart';
import 'package:expense_tracker/src/look/theme.dart';
import 'package:expense_tracker/src/notifications.dart';
import 'package:expense_tracker/src/preferences.dart';
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
    );
    final again = Preferences(file: file);
    expect(again.appearance, Appearance.dark);
    expect(again.haptics, isFalse);
    expect(again.dueAlerts, isFalse);
    expect(again.dailyNudge, isTrue);
    expect(again.nudgeHour, 22);
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
    expect(Hue.onAccent, const Color(0xFFFFFFFF));
    Shade.dark = false;
    expect(Hue.paper.computeLuminance(), greaterThan(0.8));
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
      expect(alerts.every((a) => a.quick == 'expense'), isTrue);
    });
  });
}
