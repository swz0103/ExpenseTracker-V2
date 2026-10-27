import 'package:expense_tracker/src/features/backup/model/keeper.dart';
import 'package:expense_tracker/src/features/settings/ui/sections/security_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A ledger's keys without a ledger: remembers what it was asked.
final class _Keeper implements Keeper {
  var password = '';
  var locked = false;

  @override
  String get backupFolder => '';

  @override
  Future<String> backUp() async => '';

  @override
  Future<bool> exportBackup() async => true;

  @override
  Future<bool> exportFile(String name, String text) async => true;

  @override
  Future<String?> readFile() async => null;

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
  Future<void> show(WidgetTester tester, Keeper keeper) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(children: [SecuritySection(keeper: keeper)]),
      ),
    ),
  );

  testWidgets('new passwords that differ are refused', (tester) async {
    final keeper = _Keeper();
    await show(tester, keeper);
    expect(find.text('目前不用密碼'), findsOneWidget);
    expect(find.text('鎖定帳本'), findsNothing);
    await tester.tap(find.text('設定密碼'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'secret1');
    await tester.enterText(fields.at(1), 'secret2');
    await tester.tap(find.text('設定'));
    await tester.pump();
    expect(find.text('兩次輸入的新密碼不一樣'), findsOneWidget);
    expect(keeper.hasPassword, isFalse);
  });

  testWidgets('a wrong current password is said, and lock is offered', (
    tester,
  ) async {
    final keeper = _Keeper()..password = 'secret1';
    await show(tester, keeper);
    expect(find.text('鎖定帳本'), findsOneWidget);
    await tester.tap(find.text('變更密碼'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'wrong');
    await tester.enterText(fields.at(1), 'secret2');
    await tester.enterText(fields.at(2), 'secret2');
    await tester.tap(find.text('變更'));
    await tester.pumpAndSettle();
    expect(find.text('目前的密碼不正確'), findsOneWidget);
    expect(keeper.password, 'secret1');

    await tester.tap(find.text('鎖定帳本'));
    await tester.pump();
    expect(keeper.locked, isTrue);
  });
}
