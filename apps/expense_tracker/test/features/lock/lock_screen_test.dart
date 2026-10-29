import 'dart:io';

import 'package:expense_tracker/src/features/lock/model/startup.dart';
import 'package:expense_tracker/src/features/lock/ui/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

const password = 'correct horse battery';

void main() {
  late Directory directory;
  late LedgerVault vault;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('lock-screen-');
    vault = LedgerVault(
      directory,
      codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
    );
  });

  tearDown(() => directory.deleteSync(recursive: true));

  /// A ledger with a password, set up and opened.
  Future<Startup> opened(WidgetTester tester) async {
    final startup = Startup(vault);
    await tester.runAsync(() => startup.setUp(password));
    return startup;
  }

  Future<void> show(WidgetTester tester, Startup startup) async {
    await tester.pumpWidget(MaterialApp(home: LockScreen(startup: startup)));
    await tester.pump();
  }

  /// Lets the real work behind a tap (files, key derivation) finish.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 50 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
  }

  testWidgets('a wrong password says so and keeps the ledger locked', (
    tester,
  ) async {
    final startup = await opened(tester);
    startup.lock();
    await show(tester, startup);
    expect(find.text('打開帳本'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'not the password');
    await tester.tap(find.text('打開'));
    await settle(tester, () => find.text('密碼不正確').evaluate().isNotEmpty);
    expect(find.text('密碼不正確'), findsOneWidget);
    expect(startup.state, isA<Locked>());

    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('打開'));
    await settle(tester, () => startup.state is Ready);
    expect(startup.state, isA<Ready>());
    startup.lock();
  });

  testWidgets('restoring from settings opens on the backup form, and back '
      'returns to this ledger', (tester) async {
    final startup = await opened(tester);
    startup.lockToRestore();
    await show(tester, startup);
    expect(find.text('從備份還原'), findsOneWidget);
    expect(startup.takeRestore(), isFalse, reason: 'asked once');
    await tester.tap(find.text('返回'));
    await tester.pump();
    expect(find.text('打開帳本'), findsOneWidget);
  });

  /// Plays the opening and the choices coming in.
  Future<void> settleIn(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets('a new ledger opens on the welcome and starts without a '
      'password', (tester) async {
    final startup = Startup(vault);
    expect(startup.state, isA<NeedsSetup>());
    await show(tester, startup);
    await settleIn(tester);
    expect(find.text('記帳本'), findsOneWidget);
    expect(find.text('還原備份'), findsOneWidget);
    expect(find.text('先設定密碼'), findsNothing);

    await tester.tap(find.text('建立新帳本'));
    await tester.pump();
    await settle(tester, () => startup.state is Ready);
    expect(startup.state, isA<Ready>());
    expect(startup.passwordless, isTrue);
    expect(startup.takeFresh(), isTrue, reason: 'the tour comes next');
    expect(startup.takeFresh(), isFalse, reason: 'once');
    startup.lock();
  });

  testWidgets('還原備份 opens the backup form, and back returns to the '
      'choices', (tester) async {
    final startup = Startup(vault);
    await show(tester, startup);
    await settleIn(tester);
    await tester.tap(find.text('還原備份'));
    await tester.pump();
    expect(find.text('從備份還原'), findsOneWidget);

    await tester.tap(find.text('返回'));
    await tester.pump();
    expect(find.text('建立新帳本'), findsOneWidget);
    expect(startup.state, isA<NeedsSetup>());
  });
}
