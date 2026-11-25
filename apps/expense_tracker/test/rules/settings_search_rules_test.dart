import 'dart:io';

import 'package:expense_tracker/src/app/demo/preview_services.dart';
import 'package:expense_tracker/src/app/about_section.dart';
import 'package:expense_tracker/src/app/settings_search.dart';
import 'package:expense_tracker/src/core/design_system/findable.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/design_system/design_system.dart';
import 'package:expense_tracker/src/core/formatting/setting_topic.dart';
import 'package:expense_tracker/src/core/navigation/nav.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/backup/model/drive_backup.dart';
import 'package:expense_tracker/src/features/backup/model/drive_sync.dart';
import 'package:expense_tracker/src/features/backup/model/phone_backup.dart';
import 'package:expense_tracker/src/features/backup/ui/backup_section.dart';
import 'package:expense_tracker/src/features/reminders/model/calendar_sync.dart';
import 'package:expense_tracker/src/features/reminders/ui/reminders_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_calendar.dart';
import '../support/fake_drive.dart';
import '../support/fake_folder.dart';
import '../support/places.dart';
import '../support/review_book.dart';

/// N8: every setting declares the words search finds it by, beside the
/// card that shows it, and search lists every setting so declared. A card,
/// switch, row or button on a settings page outside a [Findable] is a
/// setting search cannot find; a [Findable] whose topic its page does not
/// list ([topicsOn]) is one search never offers.
void main() {
  setUpAll(loadFonts);

  /// What a person can press or type into: each must be in a [Findable].
  bool control(Widget w) =>
      (w is InkWell && w.onTap != null) ||
      w is TickSwitch ||
      w is TextField ||
      (w is GestureDetector && w.onTap != null);

  /// The controls of the page shown that are in no [Findable], each by
  /// what it says; the topics of those built.
  (List<String>, Set<SettingTopic>) look(WidgetTester tester) {
    final loose = <String>[];
    final page = find.byType(FindScope);
    final header = find.descendant(
      of: page,
      matching: find.byType(CenterHeader),
    );
    final inHeader = {
      for (final e
          in find
              .descendant(of: header, matching: find.byWidgetPredicate(control))
              .evaluate())
        e,
    };
    for (final e
        in find
            .descendant(of: page, matching: find.byWidgetPredicate(control))
            .evaluate()) {
      if (inHeader.contains(e)) continue;
      if (e.findAncestorWidgetOfExactType<Findable>() != null) continue;
      final words = [
        for (final t
            in find
                .descendant(
                  of: find.byElementPredicate((x) => x == e),
                  matching: find.byType(Text),
                )
                .evaluate())
          (t.widget as Text).data ?? '',
      ].join(' ');
      loose.add('${e.widget.runtimeType} $words');
    }
    final built = {
      for (final e
          in find
              .descendant(of: page, matching: find.byType(Findable))
              .evaluate())
        (e.widget as Findable).topic,
    };
    return (loose, built);
  }

  /// Declared on a page but not built in these tests, and why.
  final notBuiltHere = <SettingTopic, String>{
    AboutSection.updates: 'only where the app can update itself (sideload)',
    AboutSection.sampleReset: 'only in the web preview',
    RemindersSection.phone: 'once the phone has said how it stands',
  };

  /// The topics each page built, over every way it was shown.
  final built = <SettingsDestination, Set<SettingTopic>>{};

  void check(WidgetTester tester, SettingsDestination page) {
    final (loose, topics) = look(tester);
    expect(loose, isEmpty, reason: '${page.label}: not found by search');
    (built[page] ??= {}).addAll(topics);
    for (final topic in topics) {
      expect(
        topicsOn(page),
        contains(topic),
        reason: '${topic.name} is not in ${page.label}\'s topics',
      );
    }
  }

  // The words each card on the settings' first page goes by.
  const paths = {
    SettingsDestination.importExport: '匯入與匯出',
    SettingsDestination.about: '關於',
    SettingsDestination.appearance: '外觀與操作',
    SettingsDestination.trash: '最近刪除',
    SettingsDestination.backup: '沒有自動備份',
  };

  for (final MapEntry(key: page, value: card) in paths.entries) {
    testWidgets('${page.label}: every setting is found by search', (
      tester,
    ) async {
      await show(tester, 400, 1);
      await go(tester, ['更多', '設定', card]);
      check(tester, page);
    });
  }

  for (final page in [
    SettingsDestination.reminders,
    SettingsDestination.security,
  ]) {
    testWidgets('${page.label}, with a password, a fingerprint and a '
        'calendar: every setting is found by search', (tester) async {
      final dir = Directory.systemTemp.createTempSync('settings-search-');
      addTearDown(() => dir.deleteSync(recursive: true));
      await show(
        tester,
        400,
        1,
        book: reviewLedger(),
        keys: ReviewKeys(),
        calendar: CalendarSync(FakeCalendars(), dir),
      );
      await go(tester, ['更多', '設定', page.label]);
      check(tester, page);
    });
  }

  testWidgets('備份與還原 with Google Drive and a folder: every setting is '
      'found by search', (tester) async {
    final preferences = Preferences();
    Future<void> withBackup(
      Future<void> Function(File) use, {
      bool withPhotos = true,
    }) async {}
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: FindScope(
            sought: null,
            child: SingleChildScrollView(
              child: BackupSection(
                backupManager: DemoBackupManager(),
                drive: DriveSync(
                  DriveBackup(
                    FakeDrive(),
                    token: ({required interactive}) async => 'token',
                    forget: (_) async {},
                  ),
                  preferences,
                  withBackup: withBackup,
                  revision: () => 1,
                  ledger: 'L1',
                ),
                phone: PhoneBackup(
                  FakeFolder(),
                  preferences,
                  withBackup: withBackup,
                  revision: () => 1,
                  ledger: 'L1',
                ),
                preferences: preferences,
              ),
            ),
          ),
        ),
      ),
    );
    check(tester, SettingsDestination.backup);
  });

  test('each page builds every setting it lists, but those it cannot show '
      'in a test', () {
    for (final page in SettingsDestination.values) {
      final missing = [
        for (final topic in topicsOn(page))
          if (!(built[page]?.contains(topic) ?? false) &&
              !notBuiltHere.containsKey(topic))
            topic.name,
      ];
      expect(missing, isEmpty, reason: '${page.label} lists but never built');
    }
  });

  test('no two settings share a name', () {
    final names = [for (final f in settingTopics) f.topic.name];
    expect(names.toSet().length, names.length, reason: '$names');
  });
}
