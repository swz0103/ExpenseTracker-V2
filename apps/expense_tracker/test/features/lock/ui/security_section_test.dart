import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/features/backup/model/backup_manager.dart';
import 'package:expense_tracker/src/features/lock/ui/security_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A ledger's keys without a ledger: remembers what it was asked.
final class _StubBackupManager implements BackupManager {
  var password = '';
  var locked = false;

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
    if (current != password) throw StateError('wrongSecret');
    password = next;
  }

  @override
  Future<String> newRecoveryCode() async => 'ABCD-EFGH-IJKL';

  @override
  bool get recoveryGiven => true;

  @override
  Future<void> lock() async => locked = true;

  @override
  Future<String> restoreAnother() async => '';
}

void main() {
  Future<void> show(WidgetTester tester, BackupManager backupManager) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [SecuritySection(backupManager: backupManager)],
            ),
          ),
        ),
      );

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
}
