import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

void main() {
  final root = Directory('.dart_tool/safe-mode-widget')
    ..createSync(recursive: true);

  testWidgets(
    'damaged published Ledger shows read-only safe mode after valid password',
    (tester) async {
      final work = root.createTempSync('case-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 14);
      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          await engine.lock();
        });
        final catalog = File('${work.path}/ledger/catalog.db');
        final damaged = List<int>.filled(64, 0);
        catalog.writeAsBytesSync(damaged, flush: true);

        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', 'wrong-password');
        await tap(tester, '解鎖');
        expect(find.text('解鎖帳本'), findsOneWidget);

        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        expect(find.textContaining('帳本密碼已通過'), findsOneWidget);
        expect(find.text('解鎖帳本'), findsNothing);
        expect(find.text('我的帳本'), findsNothing);
        expect(engine.isUnlocked, isFalse);
        expect(catalog.readAsBytesSync(), damaged);
        expect(tester.takeException(), isNull);
      } finally {
        await closeEngine(tester, engine);
        await tester.pumpWidget(const SizedBox());
        deleteSynthetic(work, root);
      }
    },
  );
  testWidgets(
    'authenticated profile with missing recovery key shows read-only safe mode',
    (tester) async {
      final work = root.createTempSync('case-');
      final vault = MemoryVault();
      final engine = engineAt(work, vault, schemaVersion: 14);
      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          await engine.lock();
        });
        final profile = File('${work.path}/profile.envelope');
        final retainedProfile = profile.readAsBytesSync();
        final recoveryName = vault.values.keys.singleWhere(
          (key) => key.startsWith('recovery_'),
        );
        vault.values.remove(recoveryName);

        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', 'wrong-password');
        await tap(tester, '解鎖');
        expect(find.text('解鎖帳本'), findsOneWidget);

        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        expect(find.textContaining('帳本密碼已通過'), findsOneWidget);
        expect(find.text('解鎖帳本'), findsNothing);
        expect(find.text('我的帳本'), findsNothing);
        expect(engine.isUnlocked, isFalse);
        expect(profile.readAsBytesSync(), retainedProfile);
        expect(vault.values.containsKey(recoveryName), isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await closeEngine(tester, engine);
        await tester.pumpWidget(const SizedBox());
        deleteSynthetic(work, root);
      }
    },
  );
}
