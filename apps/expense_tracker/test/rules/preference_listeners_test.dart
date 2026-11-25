import 'dart:io';

import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ledger_listeners_test.dart' show codeOf;

/// Nothing follows every setting (review 32, 3.3b): `Preferences` is not a
/// `Listenable` as a whole, so the type itself refuses
/// `listenable: preferences` and `preferences.addListener`; each page or
/// job follows `preferences.watch(topics)`, the parts it reads. A backup
/// noted in the background (its own part) then plans no reminders and
/// writes no widget, and a theme chosen builds no backup card.
///
/// Each file that follows the settings is listed in [_following] with the
/// parts it follows; one new, or one following other parts, is found here
/// and must be listed with why.
void main() {
  test('the settings as a whole cannot be followed', () {
    expect(Preferences() as Object, isNot(isA<Listenable>()));
  });

  test('each file follows only the parts listed for it', () {
    final found = <String, Set<String>>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (path == 'lib/src/core/platform/preferences.dart') continue;
      final code = codeOf(f.readAsStringSync());
      expect(
        code,
        isNot(contains('PreferenceTopic.values')),
        reason: '$path follows every part of the settings',
      );
      final topics = {
        for (final m in RegExp(r'PreferenceTopic\.(\w+)').allMatches(code))
          m[1]!,
      };
      if (topics.isNotEmpty) found[path] = topics;
    }
    expect(
      found,
      {for (final MapEntry(:key, :value) in _following.entries) key: value.$1},
      reason:
          'Follow the parts read, and list the file in _following with '
          'why.',
    );
  });

  test('what a background backup notes is followed by nothing that plans '
      'the reminders or writes the widget', () {
    for (final path in [
      'lib/src/features/reminders/model/reminder_alerts.dart',
      'lib/src/features/overview/model/home_widget.dart',
      'lib/src/app/app.dart',
    ]) {
      final (topics, _) = _following[path]!;
      expect(topics, isNot(contains('driveBackup')), reason: path);
      expect(topics, isNot(contains('phoneBackup')), reason: path);
    }
  });
}

/// Who follows which parts of the settings, and why.
const _following = <String, (Set<String>, String)>{
  'lib/src/app/app.dart': (
    {'look'},
    'The colours and the taps felt, applied to the whole app.',
  ),
  'lib/src/app/about_section.dart': ({'updates'}, '自動檢查新版本.'),
  'lib/src/app/settings_page.dart': (
    {
      'look',
      'reminders',
      'phoneBackup',
      'driveBackup',
      'homeWidget',
      'trading',
    },
    'The index cards say the look, the reminders on and the backups; '
        '外觀與操作 says the widget and the discount.',
  ),
  'lib/src/features/backup/ui/backup_section.dart': (
    {'phoneBackup', 'driveBackup'},
    'The folder and Drive cards.',
  ),
  'lib/src/features/lock/ui/security_section.dart': ({'lock'}, '自動上鎖.'),
  'lib/src/features/overview/model/home_widget.dart': (
    {'homeWidget'},
    'The figures the widget shows, its one setting.',
  ),
  'lib/src/features/overview/ui/overview.dart': ({'overview'}, "總覽's blocks."),
  'lib/src/features/reminders/model/reminder_alerts.dart': (
    {'reminders'},
    'The plan of reminders: what is on, and when.',
  ),
  'lib/src/features/reminders/ui/reminders_section.dart': (
    {'reminders'},
    'The nudge time panel.',
  ),
  'lib/src/features/settings/ui/preferences_section.dart': (
    {'look', 'homeWidget', 'trading'},
    'The look, widget and discount panels.',
  ),
};
