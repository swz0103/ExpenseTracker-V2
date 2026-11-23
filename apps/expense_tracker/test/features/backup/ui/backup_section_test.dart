import 'dart:io';

import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/design_system/design_system.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/backup/model/backup_manager.dart';
import 'package:expense_tracker/src/features/backup/model/drive_backup.dart';
import 'package:expense_tracker/src/features/backup/model/drive_sync.dart';
import 'package:expense_tracker/src/features/backup/model/phone_backup.dart';
import 'package:expense_tracker/src/features/backup/ui/backup_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_drive.dart';
import '../../../support/fake_folder.dart';
import '../../../support/places.dart';

/// The ledger's keys, answering as told.
final class _Keys implements BackupManager {
  @override
  var hasPassword = false;
  @override
  var recoveryGiven = false;

  /// What exporting does: saved, cancelled, or this error.
  var saves = true;
  Exception? exportFails;
  Exception? restoreFails;
  var exports = 0;
  var restores = 0;

  @override
  DateTime? exportedAt;

  @override
  Future<bool> exportBackup() async {
    exports++;
    if (exportFails case final error?) throw error;
    if (saves) exportedAt = DateTime.now();
    return saves;
  }

  @override
  Future<String> newRecoveryCode() async {
    recoveryGiven = true;
    return 'ABCD-EFGH-JKMN-PQRS';
  }

  @override
  Future<String> restoreAnother() async {
    restores++;
    if (restoreFails case final error?) throw error;
    return 'kept.etbk';
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by 備份與還原');
}

void main() {
  late Directory directory;
  late _Keys keys;
  late Preferences preferences;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('backup-section-');
    keys = _Keys();
    preferences = Preferences();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  /// A backup file to send, as the ledger writes one.
  Future<void> withBackup(
    Future<void> Function(File file) use, {
    bool withPhotos = true,
  }) async {
    final file = File('${directory.path}/記帳本.etbk')..writeAsStringSync('x');
    await use(file);
  }

  DriveSync drive({bool allowed = true}) => DriveSync(
    DriveBackup(
      FakeDrive(),
      token: ({required interactive}) async => allowed ? 'token' : null,
      forget: (_) async {},
    ),
    preferences,
    withBackup: withBackup,
    revision: () => 1,
    ledger: 'L1',
  );

  PhoneBackup phone(FakeFolder folder) => PhoneBackup(
    folder,
    preferences,
    withBackup: (use) => withBackup(use),
    revision: () => 1,
    ledger: 'L1',
  );

  Future<void> open(
    WidgetTester tester, {
    DriveSync? drive,
    PhoneBackup? phone,
  }) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BackupSection(
              backupManager: keys,
              drive: drive,
              phone: phone,
              preferences: preferences,
            ),
          ),
        ),
      ),
    );
  }

  /// Lets the files a backup reads and writes finish, then the screen.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
  }

  /// The tick that turns a way of backing up on or off.
  Finder tick(String title) =>
      find.byWidgetPredicate((w) => w is TickSwitch && w.label == title);

  /// Presses what a screen reader calls [words], the last one when a
  /// sheet repeats a page's words.
  Future<void> tap(WidgetTester tester, String words) async {
    await go(tester, ['^$words']);
    await settle(tester);
  }

  group('匯出一份', () {
    testWidgets('without a password, the first time shows a recovery code', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('沒有自動備份'), findsOneWidget);
      await tap(tester, '匯出一份');
      expect(find.text('新的救援碼'), findsOneWidget);
      expect(find.textContaining('在新手機還原這份備份時要輸入它'), findsOneWidget);
      await tap(tester, '存好了');
      expect(keys.exports, 1);

      // Given once: the next export keeps it.
      await tap(tester, '匯出一份');
      expect(find.text('新的救援碼'), findsNothing);
      expect(find.text('已匯出備份檔，還原時輸入你抄下的救援碼'), findsOneWidget);
    });

    testWidgets('cancelled, the new code is shown all the same', (
      tester,
    ) async {
      keys.saves = false;
      await open(tester);
      await tap(tester, '匯出一份');
      expect(find.textContaining('之前的救援碼不再適用'), findsOneWidget);
    });

    testWidgets('with a password, no code', (tester) async {
      keys.hasPassword = true;
      await open(tester);
      await tap(tester, '匯出一份');
      expect(find.text('新的救援碼'), findsNothing);
      expect(find.text('已匯出備份檔'), findsOneWidget);
    });

    testWidgets('after an export the page no longer says 還沒有備份 (F46)', (
      tester,
    ) async {
      keys.hasPassword = true;
      await open(tester);
      expect(find.text('還沒有備份'), findsOneWidget);
      await tap(tester, '匯出一份');
      expect(find.text('還沒有備份'), findsNothing);
      expect(find.textContaining('上次 今天 '), findsOneWidget);
      // No automatic backup is on, which it still says.
      expect(find.text('沒有自動備份'), findsOneWidget);
    });

    testWidgets('a failure is said', (tester) async {
      keys
        ..hasPassword = true
        ..exportFails = const FileSystemException('disk full');
      await open(tester);
      await tap(tester, '匯出一份');
      expect(find.textContaining('匯出失敗：'), findsOneWidget);
    });
  });

  group('還原', () {
    testWidgets('asks first, and nothing happens on 取消', (tester) async {
      await open(tester);
      await tap(tester, '還原');
      expect(find.textContaining('會先把目前的帳本連同照片備份一份'), findsOneWidget);
      await tap(tester, '取消');
      expect(keys.restores, 0);
      await tap(tester, '還原');
      await tap(tester, '選擇備份');
      expect(keys.restores, 1);
    });

    testWidgets('a restore that cannot start says why', (tester) async {
      keys.restoreFails = const FileSystemException('no room');
      await open(tester);
      await tap(tester, '還原');
      await tap(tester, '選擇備份');
      expect(find.textContaining('沒有開始還原：'), findsOneWidget);
    });
  });

  group('Google 雲端硬碟', () {
    testWidgets('linking sends the first backup and says when', (tester) async {
      keys.hasPassword = true;
      final sync = drive();
      addTearDown(sync.dispose);
      await open(tester, drive: sync);
      await tester.tap(tick('Google 雲端硬碟'));
      await settle(tester);
      expect(sync.linked, isTrue);
      expect(find.text('已把帳本備份到 Google 雲端硬碟，之後有變動就每天一次'), findsOneWidget);
      expect(find.text('上次備份'), findsWidgets);
      expect(find.textContaining('今天'), findsWidgets);
      expect(find.text('沒有自動備份'), findsNothing);
      // Which Google account it goes to (F90).
      expect(find.text('帳號'), findsOneWidget);
      expect(find.text('me@example.com'), findsOneWidget);

      // Stopping asks first, and leaves what is on Drive.
      await tester.tap(tick('Google 雲端硬碟'));
      await settle(tester);
      await tap(tester, '停止');
      expect(sync.linked, isFalse);
      expect(find.text('已停止雲端硬碟備份'), findsOneWidget);
      expect(find.text('沒有自動備份'), findsOneWidget);
    });

    testWidgets('with the photos, backups wait for Wi-Fi unless the person '
        'turns that off (AND-05)', (tester) async {
      preferences.update(driveLinked: true, drivePhotos: true);
      var onWifi = false;
      var sent = 0;
      final sync = DriveSync(
        DriveBackup(
          FakeDrive(),
          token: ({required interactive}) async => 'token',
          forget: (_) async {},
        ),
        preferences,
        withBackup: (use, {withPhotos = true}) async {
          sent++;
          await withBackup(use);
        },
        revision: () => 1,
        ledger: 'L1',
        unmetered: () async => onWifi,
      );
      addTearDown(sync.dispose);
      await open(tester, drive: sync);
      expect(find.text('連 Wi-Fi 時一起備份'), findsOneWidget);
      // On mobile data: waits.
      expect(await tester.runAsync(sync.backUpIfDue), isFalse);
      expect(sent, 0);

      await tester.tap(find.byKey(Keys.photosOnWifi));
      await tester.pump();
      expect(preferences.photosOnWifi, isFalse);
      expect(find.text('任何網路都一起備份'), findsOneWidget);
      // Now it goes on mobile data too.
      expect(await tester.runAsync(sync.backUpIfDue), isTrue);
      expect(sent, 1);
    });

    testWidgets('a sign-in turned down links nothing', (tester) async {
      keys.hasPassword = true;
      final sync = drive(allowed: false);
      addTearDown(sync.dispose);
      await open(tester, drive: sync);
      await tester.tap(tick('Google 雲端硬碟'));
      await settle(tester);
      expect(sync.linked, isFalse);
      expect(find.text('沒有連結 Google 雲端硬碟'), findsOneWidget);
    });
  });

  group('存到資料夾', () {
    testWidgets('says which folders Android allows, then backs up into one', (
      tester,
    ) async {
      final folder = FakeFolder();
      final backup = phone(folder);
      addTearDown(backup.dispose);
      await open(tester, phone: backup);
      await tester.tap(tick('存到資料夾'));
      await settle(tester);
      expect(find.textContaining('Android 不讓 App 直接用「下載」'), findsOneWidget);
      await tap(tester, '選資料夾');
      expect(find.text('已備份到「備份」，之後每週自動備份'), findsOneWidget);
      expect(folder.files, hasLength(1));
      expect(backup.daily, isFalse);
      await tap(tester, '多久一次');
      expect(backup.daily, isTrue);
      expect(find.textContaining('每天'), findsWidgets);

      await tester.tap(tick('存到資料夾'));
      await settle(tester);
      await tap(tester, '停止');
      expect(backup.on, isFalse);
      expect(find.text('已停止備份到手機資料夾'), findsOneWidget);
    });

    testWidgets('a folder Android will not keep asks to choose again', (
      tester,
    ) async {
      final folder = FakeFolder()..rejects = true;
      final backup = phone(folder);
      addTearDown(backup.dispose);
      await open(tester, phone: backup);
      await tester.tap(tick('存到資料夾'));
      await settle(tester);
      await tap(tester, '選資料夾');
      expect(find.textContaining('Android 不讓 App 存到這個位置'), findsOneWidget);
      folder.rejects = false;
      await tap(tester, '重新選');
      expect(backup.on, isTrue);
      expect(find.textContaining('已備份到「備份」'), findsOneWidget);
    });

    testWidgets('取消 at the rules opens no chooser', (tester) async {
      final backup = phone(FakeFolder());
      addTearDown(backup.dispose);
      await open(tester, phone: backup);
      await tester.tap(tick('存到資料夾'));
      await settle(tester);
      await tap(tester, '取消');
      expect(backup.on, isFalse);
    });
  });
}
