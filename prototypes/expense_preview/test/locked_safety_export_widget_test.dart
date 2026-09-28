import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  final root = Directory('.dart_tool/locked-safety-widget')
    ..createSync(recursive: true);

  for (final recovery in [false, true]) {
    testWidgets('blocked profile exports verified safety with '
        '${recovery ? 'recovery text' : 'password'}', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final work = root.createTempSync('case-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 14);
      final documents = Documents();
      try {
        late String recoveryKey;
        late List<int> before;
        await tester.runAsync(() async {
          recoveryKey = await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          final earlier = await engine.exportBackup();
          await engine.post(income(a));
          before = await EnvelopeCodec().openWithPassword(
            await engine.exportBackup(),
            password,
          );
          await engine.importBackup(earlier, password, recovery: false);
          await engine.lock();
          File('${work.path}/profile.pending').writeAsStringSync('damaged');
        });

        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: documents),
        );
        await settle(tester);
        expect(find.text('匯出還原前加密安全副本'), findsOneWidget);
        await input(tester, '原帳本密碼', 'wrong-password');
        await tap(tester, '匯出還原前加密安全副本');
        expect(documents.saved, isNull);
        if (recovery) {
          await tester.tap(find.widgetWithText(SwitchListTile, '使用救援文字'));
          await tester.pumpAndSettle();
        }
        await input(
          tester,
          recovery ? '原帳本救援文字' : '原帳本密碼',
          recovery ? recoveryKey : password,
        );
        await tap(tester, '匯出還原前加密安全副本');
        await tester.runAsync(() async {
          expect(
            await EnvelopeCodec().openWithPassword(documents.saved!, password),
            before,
          );
          expect(File('${work.path}/profile.pending').existsSync(), isTrue);
          expect(engine.isUnlocked, isFalse);
        });
        expect(tester.takeException(), isNull);
      } finally {
        await closeEngine(tester, engine);
        await tester.pumpWidget(const SizedBox());
        deleteSynthetic(work, root);
      }
    });
  }
}
