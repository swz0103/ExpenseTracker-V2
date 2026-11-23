// Work package 3.1: one lock gate above every screen. Fixed in 3.1; kept as
// regression tests of SEC-05 and SEC-03.
import 'dart:async';
import 'dart:io';

import 'package:expense_tracker/src/app/bootstrap.dart';
import 'package:expense_tracker/src/app/shell.dart';
import 'package:expense_tracker/src/core/design_system/feedback.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('p3-1-'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets(
    'SEC-05: locking closes a sheet that is open, so no book shows over the '
    'lock screen',
    (tester) async {
      final startup = Startup(
        LedgerVault(
          dir,
          codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
        ),
      );
      await tester.runAsync(() => startup.setUp('correct horse battery'));
      await tester.pumpWidget(
        VaultRoot(startup: startup, preferences: Preferences()),
      );
      // The ledger opens on the real encrypted store.
      for (var i = 0; i < 50 && find.byType(AppShell).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.byType(AppShell), findsOneWidget);
      // A sheet is open over the book.
      final context = tester.element(find.byType(AppShell));
      unawaited(showSheet<void>(context, (_) => const Text('帳務內容')));
      await tester.pumpAndSettle();
      expect(find.text('帳務內容'), findsOneWidget);
      // The phone locks.
      startup.lock();
      await tester.pumpAndSettle();
      expect(find.text('帳務內容'), findsNothing);
    },
  );

  LedgerVault vault() =>
      LedgerVault(dir, codec: KeyringCodec(kdf: PasswordKdf.insecureForTests));

  test(
    'SEC-03: after ten wrong passwords the right one is not accepted at once',
    () async {
      const password = 'correct horse battery';
      final first = Startup(vault());
      await first.setUp(password);
      first.lock();
      final startup = Startup(vault());
      for (var i = 0; i < 10; i++) {
        try {
          await startup.unlockWithPassword('wrong password $i');
        } on KeyringException {
          // Each wrong one is refused.
        } on UnlockDelayed {
          // Or, after too many, not tried at all (the API 3.1 added).
        }
      }
      try {
        await startup.unlockWithPassword(password);
      } on Object {
        // A lock-out may refuse by throwing.
      }
      expect(startup.state, isNot(isA<Ready>()));
    },
  );
}
