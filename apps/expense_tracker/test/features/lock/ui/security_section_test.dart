import 'dart:io';

import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/platform/screen_privacy.dart';
import 'package:expense_tracker/src/features/backup/model/backup_manager.dart';
import 'package:expense_tracker/src/features/lock/ui/security_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

/// A ledger's keys without a ledger: remembers what it was asked.
final class _StubBackupManager implements BackupManager {
  var password = '';
  var locked = false;

  /// What changing the password, or making a new code, fails with.
  Object? fails;
  Object? codeFails;
  var codes = 0;

  @override
  Future<bool> exportBackup() async => true;

  @override
  Future<bool> exportFile(String name, String text) async => true;

  @override
  Future<String?> readFile() async => null;

  @override
  Future<bool> exportBytes(String name, List<int> bytes) async => true;

  @override
  DateTime? get cloudCopyAt => null;

  @override
  DateTime? get googleTakenAt => null;

  @override
  bool get hasPassword => password.isNotEmpty;

  @override
  Future<void> setPassword(String next) async => password = next;

  @override
  Future<void> changePassword(String current, String next) async {
    if (fails case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    if (current != password) throw StateError('wrongSecret');
    password = next;
  }

  @override
  Future<String> newRecoveryCode() async {
    if (codeFails case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    codes++;
    return 'ABCD-EFGH-IJKL';
  }

  @override
  bool get recoveryGiven => true;

  @override
  Future<void> lock() async => locked = true;

  @override
  Future<String> restoreAnother() async => '';
}

void main() {
  Future<void> show(
    WidgetTester tester,
    BackupManager? backupManager, {
    ScreenPrivacy? privacy,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            SecuritySection(backupManager: backupManager, privacy: privacy),
          ],
        ),
      ),
    ),
  );

  /// Opens 密碼 and types [fields] into its fields, then 變更.
  Future<void> change(WidgetTester tester, List<String> fields) async {
    await tester.tap(find.byKey(Keys.password));
    await tester.pumpAndSettle();
    for (final (i, text) in fields.indexed) {
      await tester.enterText(find.byType(TextField).at(i), text);
    }
    await tester.tap(find.byKey(Keys.changePassword));
    await tester.pumpAndSettle();
  }

  testWidgets('new passwords that differ are refused', (tester) async {
    final backupManager = _StubBackupManager();
    await show(tester, backupManager);
    expect(find.text('還沒設定 · 點了設定'), findsOneWidget);
    expect(find.text('現在鎖上'), findsNothing);
    await tester.tap(find.byKey(Keys.password));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'secret1');
    await tester.enterText(fields.at(1), 'secret2');
    await tester.tap(find.byKey(Keys.changePassword));
    await tester.pump();
    expect(find.text('兩次輸入的新密碼不一樣'), findsOneWidget);
    expect(backupManager.hasPassword, isFalse);
  });

  testWidgets('a wrong current password is said, and lock is offered', (
    tester,
  ) async {
    final backupManager = _StubBackupManager()..password = 'secret1';
    await show(tester, backupManager);
    expect(find.text('現在鎖上'), findsOneWidget);
    await tester.tap(find.byKey(Keys.password));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'wrong');
    await tester.enterText(fields.at(1), 'secret2');
    await tester.enterText(fields.at(2), 'secret2');
    await tester.tap(find.byKey(Keys.changePassword));
    await tester.pumpAndSettle();
    expect(find.text('目前的密碼不正確'), findsOneWidget);
    expect(backupManager.password, 'secret1');

    await tester.tap(find.byKey(Keys.lockNow));
    await tester.pump();
    expect(backupManager.locked, isTrue);
  });

  testWidgets('the first password set shows the recovery code once, then '
      'says it is set', (tester) async {
    final backupManager = _StubBackupManager();
    await show(tester, backupManager);
    await change(tester, ['secret1', 'secret1']);
    expect(backupManager.password, 'secret1');
    expect(find.text('新的救援碼'), findsOneWidget);
    expect(find.text('密碼設好了。忘記密碼時，只有它能打開帳本'), findsOneWidget);
    await go(tester, ['存好了']);
    expect(find.text('新的救援碼'), findsNothing);
    expect(find.text('已設定密碼'), findsOneWidget);
    expect(find.text('已設定 · 點了變更'), findsOneWidget);
    expect(find.text('現在鎖上'), findsOneWidget);
  });

  testWidgets('a password changed says so', (tester) async {
    final backupManager = _StubBackupManager()..password = 'secret1';
    await show(tester, backupManager);
    await change(tester, ['secret1', 'secret2', 'secret2']);
    expect(backupManager.password, 'secret2');
    expect(find.text('密碼已變更'), findsOneWidget);
    expect(backupManager.codes, 0, reason: 'the code stays');
  });

  testWidgets('a password too short, or a failure, is said by its kind', (
    tester,
  ) async {
    final backupManager = _StubBackupManager()
      ..password = 'secret1'
      ..fails = StateError('weakPassword');
    await show(tester, backupManager);
    await change(tester, ['secret1', 'abc', 'abc']);
    expect(find.text('新密碼至少要 6 個字'), findsOneWidget);

    backupManager.fails = const FileSystemException('disk full');
    await change(tester, ['secret1', 'secret2', 'secret2']);
    expect(find.textContaining('無法變更密碼（'), findsOneWidget);
    expect(backupManager.password, 'secret1');
  });

  testWidgets('救援碼 makes a new code only once agreed, and shows it', (
    tester,
  ) async {
    final backupManager = _StubBackupManager()..password = 'secret1';
    await show(tester, backupManager);
    await go(tester, ['忘記密碼、換手機用']);
    expect(find.text('換一組新的？舊的會立刻失效'), findsOneWidget);
    await go(tester, ['取消']);
    expect(backupManager.codes, 0);

    await go(tester, ['忘記密碼、換手機用']);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(backupManager.codes, 1);
    expect(find.text('新的救援碼'), findsOneWidget);
    expect(find.text('忘記密碼時，只有它能打開帳本'), findsOneWidget);
  });

  testWidgets('a new code that cannot be made says so', (tester) async {
    final backupManager = _StubBackupManager()
      ..codeFails = StateError('keystore');
    await show(tester, backupManager);
    await go(tester, ['忘記密碼、換手機用']);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(find.textContaining('沒有換成：'), findsOneWidget);
    expect(find.text('新的救援碼'), findsNothing);
  });

  testWidgets('禁止截圖 is turned on and off, and the card says what it '
      'does', (tester) async {
    final privacy = ScreenPrivacy.inMemory();
    await show(tester, null, privacy: privacy);
    expect(find.text('密碼'), findsNothing, reason: 'no keys to show');
    expect(find.text('最近使用畫面已自動遮住'), findsOneWidget);
    await go(tester, ['禁止截圖']);
    expect(privacy.on, isTrue);
    expect(find.text('截圖、錄影都擋下'), findsOneWidget);
    await go(tester, ['截圖、錄影都擋下']);
    expect(privacy.on, isFalse);
  });

  testWidgets('a phone that cannot hide its screen says so', (tester) async {
    final directory = Directory.systemTemp.createTempSync('privacy-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final privacy = ScreenPrivacy(
      directory,
      (on) async => throw StateError('no window'),
    );
    await show(tester, null, privacy: privacy);
    await go(tester, ['禁止截圖']);
    for (var i = 0; i < 50; i++) {
      if (find.text('這支手機無法切換截圖設定').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('這支手機無法切換截圖設定'), findsOneWidget);
  });
}
