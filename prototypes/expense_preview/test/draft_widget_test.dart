import 'dart:async';
import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  testWidgets(
    'partial input survives lock, resumes, validates and posts once; new form stays clean',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('draft-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 7);
      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '記一筆');
        await input(tester, '金額（正數）', '12.');
        await input(tester, '日期（YYYY-MM-DD）', '2026-');
        await tester.tap(find.byTooltip('鎖定'));
        await settle(tester);
        expect(find.widgetWithText(TextField, '金額（正數）'), findsNothing);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '繼續草稿');
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '金額（正數）'))
              .controller!
              .text,
          '12.',
        );
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, '日期（YYYY-MM-DD）'),
              )
              .controller!
              .text,
          '2026-',
        );
        await tester.scrollUntilVisible(
          find.text('儲存收支').hitTestable(),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tap(tester, '儲存收支');
        expect(find.text('繼續草稿'), findsNothing);
        await input(tester, '金額（正數）', '12.50');
        await input(tester, '日期（YYYY-MM-DD）', '2026-09-27');
        await tap(tester, '返回帳本');
        await tester.scrollUntilVisible(
          find.text('匯出加密備份').hitTestable(),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tap(tester, '匯出加密備份');
        await tester.scrollUntilVisible(
          find.byKey(const Key('message')),
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('請先繼續或捨棄本機草稿，再進行此操作。'), findsOneWidget);
        await tap(tester, '繼續草稿');
        await tester.scrollUntilVisible(
          find.text('儲存收支').hitTestable(),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tap(tester, '儲存收支');
        expect(find.text('繼續草稿'), findsNothing);
        await tester.runAsync(() async {
          expect((await engine.entries()).length, 2);
          expect(
            (await engine.accounts()).single.balance.minorUnits,
            BigInt.from(8750),
          );
        });
        await tap(tester, '記一筆');
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '金額（正數）'))
              .controller!
              .text,
          '',
        );
        await input(tester, '金額（正數）', '99');
        await tap(tester, '返回帳本');
        final discard = find.text('捨棄草稿');
        await tester.ensureVisible(discard);
        await tester.tap(discard);
        await tester.pump(const Duration(milliseconds: 300));
        await tap(tester, '保留');
        await tester.scrollUntilVisible(
          find.text('繼續草稿'),
          -250,
          scrollable: find.byType(Scrollable).first,
        );

        expect(find.text('繼續草稿'), findsOneWidget);
        await tester.tap(find.text('捨棄草稿'));
        await tester.pump(const Duration(milliseconds: 300));
        await tap(tester, '確認捨棄');
        expect(find.text('繼續草稿'), findsNothing);
        await tester.runAsync(() async {
          expect((await engine.entries()).length, 2);
        });
      } finally {
        await tester.pumpWidget(const SizedBox());
        await closeEngine(tester, engine);
        deleteSynthetic(work, Directory('.dart_tool/widget-tests'));
      }
    },
  );
  testWidgets(
    'saving indicator precedes vault completion and failed first save can retry',
    (tester) async {
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('draft-status-');
      final vault = MemoryVault();
      final engine = engineAt(work, vault, schemaVersion: 7);
      final release = Completer<void>();
      var held = false;
      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '記一筆');
        vault.failWrites = true;
        vault.beforeRead = (name) async {
          if (name.startsWith('manual_draft_key_') && !held) {
            held = true;
            await release.future;
          }
        };
        await input(tester, '金額（正數）', '12');
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('draft-status')));
        expect(find.text('正在加密保存草稿…'), findsOneWidget);
        release.complete();
        for (
          var i = 0;
          i < 120 && find.text('草稿保存失敗，請重試；尚未安全保存。').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        expect(find.text('草稿保存失敗，請重試；尚未安全保存。'), findsOneWidget);
        vault.failWrites = false;
        vault.beforeRead = null;
        await input(tester, '金額（正數）', '13');
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('draft-status')));
        for (
          var i = 0;
          i < 120 && find.text('草稿已加密保存；尚未影響餘額。').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        expect(find.text('草稿已加密保存；尚未影響餘額。'), findsOneWidget);
        await tap(tester, '返回帳本');
        await tester.scrollUntilVisible(
          find.text('繼續草稿'),
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        await tap(tester, '繼續草稿');
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '金額（正數）'))
              .controller!
              .text,
          '13',
        );
      } finally {
        if (!release.isCompleted) release.complete();
        vault.failWrites = false;
        vault.beforeRead = null;
        await tester.pumpWidget(const SizedBox());
        await closeEngine(tester, engine);
        deleteSynthetic(work, root);
      }
    },
  );
}
