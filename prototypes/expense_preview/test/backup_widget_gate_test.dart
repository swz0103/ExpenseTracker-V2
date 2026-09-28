import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  final root = Directory('.dart_tool/backup-widget-gate')
    ..createSync(recursive: true);

  for (final recovery in [false, true]) {
    testWidgets(
      'schema 14 document restore locks and ${recovery ? 'recovery' : 'password'} confirmation preserves a safety copy',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final work = root.createTempSync('case-');
        final engine = engineAt(work, MemoryVault(), schemaVersion: 14);
        final documents = Documents();
        late String recoveryKey;
        late List<int> replacedPlain;
        try {
          await tester.runAsync(() async {
            recoveryKey = await setup(engine);
            final a = account(engine);
            await engine.createAccount(a, opening(a));
            await engine.post(income(a));
            documents.saved = await engine.exportBackup();
            await engine.post(income(a));
            replacedPlain = await EnvelopeCodec().openWithPassword(
              await engine.exportBackup(),
              password,
            );
            await engine.lock();
          });
          documents.onOpen = () => tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          await tester.pumpWidget(
            PreviewApp(engine: Future.value(engine), documents: documents),
          );
          await settle(tester);
          await input(tester, '密碼', password);
          await tap(tester, '解鎖');
          await tester.scrollUntilVisible(
            find.text('從檔案還原'),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tap(tester, '從檔案還原');
          expect(engine.isUnlocked, isFalse);
          expect(find.text('已選取加密備份；解鎖後繼續確認還原。'), findsOneWidget);
          await input(tester, '密碼', password);
          await tap(tester, '解鎖');
          expect(find.text('還原加密備份'), findsOneWidget);

          await input(tester, '備份的密碼', 'incorrect-password');
          await tap(tester, '確認取代並還原');
          await tester.runAsync(() async {
            expect(
              (await engine.accounts()).single.balance,
              Money.parse(Currency('TWD', 2), '114'),
            );
            expect(await engine.hasSafetyCopy(), isFalse);
          });

          if (recovery) {
            await tester.tap(find.widgetWithText(SwitchListTile, '使用救援文字'));
            await tester.pumpAndSettle();
          }
          await input(
            tester,
            recovery ? '備份的救援文字' : '備份的密碼',
            recovery ? recoveryKey : password,
          );
          await tap(tester, '確認取代並還原');
          await tester.runAsync(() async {
            expect(
              (await engine.accounts()).single.balance,
              Money.parse(Currency('TWD', 2), '107'),
            );
            expect(await engine.hasSafetyCopy(), isTrue);
          });
          await tester.scrollUntilVisible(
            find.text('匯出最近一次還原前副本'),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tap(tester, '匯出最近一次還原前副本');
          await tester.runAsync(() async {
            expect(
              await EnvelopeCodec().openWithPassword(
                documents.saved!,
                password,
              ),
              replacedPlain,
            );
          });
          expect(tester.takeException(), isNull);
        } finally {
          await closeEngine(tester, engine);
          await tester.pumpWidget(const SizedBox());
          deleteSynthetic(work, root);
        }
      },
    );
  }
}
