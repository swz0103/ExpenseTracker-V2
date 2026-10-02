import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

void main() {
  testWidgets(
    'system back saves the draft before returning then locks on exit',
    (tester) async {
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('safe-back-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 12);
      var exits = 0;
      try {
        await tester.runAsync(() async {
          await setup(engine);
          final cash = account(engine);
          await engine.createAccount(cash, opening(cash));
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(
            engine: Future.value(engine),
            documents: Documents(),
            exitApp: () async => exits++,
          ),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '記一筆');
        await input(tester, '金額（正數）', '12');

        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(find.text('繼續草稿'), findsOneWidget);
        expect(exits, 0);
        await tester.runAsync(() async {
          expect((await engine.entryDraft())?.fields.amount, '12');
        });

        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(exits, 1);
        expect(engine.isUnlocked, isFalse);
        expect(find.widgetWithText(TextField, '密碼'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await closeEngine(tester, engine);
        deleteSynthetic(work, root);
      }
    },
  );

  testWidgets('draft save failure blocks system back', (tester) async {
    final root = Directory('.dart_tool/widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('blocked-back-');
    final vault = MemoryVault();
    final engine = engineAt(work, vault, schemaVersion: 12);
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final cash = account(engine);
        await engine.createAccount(cash, opening(cash));
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
      await input(tester, '金額（正數）', '12');
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

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('繼續草稿'), findsNothing);
      expect(find.widgetWithText(TextField, '金額（正數）'), findsOneWidget);
      expect(engine.isUnlocked, isTrue);

      vault.failWrites = false;
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('繼續草稿'), findsOneWidget);
    } finally {
      vault.failWrites = false;
      await tester.pumpWidget(const SizedBox());
      await closeEngine(tester, engine);
      deleteSynthetic(work, root);
    }
  });

  testWidgets('system back closes a modal before requesting app exit', (
    tester,
  ) async {
    final root = Directory('.dart_tool/widget-tests')
      ..createSync(recursive: true);
    final work = root.createTempSync('modal-back-');
    final engine = engineAt(work, MemoryVault(), schemaVersion: 12);
    var exits = 0;
    try {
      await tester.runAsync(() async {
        await setup(engine);
        final cash = account(engine);
        await engine.createAccount(cash, opening(cash));
        await engine.lock();
      });
      await tester.pumpWidget(
        PreviewApp(
          engine: Future.value(engine),
          documents: Documents(),
          exitApp: () async => exits++,
        ),
      );
      await settle(tester);
      await input(tester, '密碼', password);
      await tap(tester, '解鎖');
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      expect(find.text('立即鎖定'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('立即鎖定'), findsNothing);
      expect(exits, 0);
      expect(engine.isUnlocked, isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await closeEngine(tester, engine);
      deleteSynthetic(work, root);
    }
  });
}
