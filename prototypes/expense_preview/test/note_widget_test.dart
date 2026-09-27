import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  testWidgets(
    'note edit at narrow large text preserves draft on lock and hides note after saving',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory('.dart_tool/widget-tests')
            ..createSync(recursive: true),
          work = root.createTempSync('note-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 12);
      late PublicId original;
      Future<void> visible(Finder f) async {
        if (f.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            f,
            180,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
      }

      Future<void> button(String text) async {
        await visible(find.text(text));
        await tap(tester, text);
      }

      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          final p = income(a);
          original = p.id;
          await engine.post(p);
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        final edit = find.byKey(ValueKey('entry-note-edit-$original'));
        await visible(edit);
        await tester.tap(edit);
        await settle(tester);
        await visible(find.byKey(const Key('note-text')));
        await tester.enterText(
          find.byKey(const Key('note-text')),
          '私人內容 123.45🙂',
        );
        await settle(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await settle(tester);
        expect(find.text('私人內容 123.45🙂'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await button('繼續草稿');
        await visible(find.byKey(const Key('note-text')));
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('note-text')))
              .controller!
              .text,
          '私人內容 123.45🙂',
        );
        await button('儲存備註');
        await tester.runAsync(() async {
          expect((await engine.entryNote(original)).revision, 1);
          expect(await engine.entries(), hasLength(2));
        });
        final note = find.byKey(ValueKey('entry-note-$original'));
        await visible(note);
        expect(tester.widget<Text>(note).data, '私人內容 123.45🙂');
        await tester.tap(find.byTooltip('隱藏金額'));
        await settle(tester);
        await visible(note);
        expect(tester.widget<Text>(note).data, '備註已隱藏');
        expect(find.text('私人內容 123.45🙂'), findsNothing);
        expect(tester.takeException(), null);
      } finally {
        await closeEngine(tester, engine);
        deleteSynthetic(work, root);
      }
    },
  );
}
