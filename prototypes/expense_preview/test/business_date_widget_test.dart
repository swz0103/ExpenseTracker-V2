import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  testWidgets(
    'opening and expense calendar dates use the draft and strict submission path',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('date-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 7);
      Future<void> button(String label) async {
        await tester.scrollUntilVisible(
          find.text(label).hitTestable(),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tap(tester, label);
      }

      Future<void> leapDay() async {
        final picker = find.byTooltip('選擇日期');
        await tester.ensureVisible(picker);
        await tester.pumpAndSettle();
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(find.text('29').hitTestable());
        await tester.tap(find.text('確定'));
        await tester.pumpAndSettle();
        await settle(tester);
      }

      try {
        await tester.runAsync(() async {
          await setup(engine);
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '新增帳戶');
        await input(tester, '帳戶名稱', '日曆現金');
        await input(tester, '期初餘額', '100');
        await input(tester, '起始日期（YYYY-MM-DD）', '2024-02-28');
        await leapDay();
        await button('建立帳戶');
        await tester.runAsync(() async {
          expect(
            (await engine.accounts()).single.account.openedOn.toString(),
            '2024-02-29',
          );
        });
        await tap(tester, '記一筆');
        await input(tester, '金額（正數）', '12.50');
        await input(tester, '日期（YYYY-MM-DD）', '2023-02-29');
        await button('儲存收支');
        await tester.runAsync(() async {
          expect(await engine.entries(), hasLength(1));
          expect((await engine.entryDraft())!.fields.date, '2023-02-29');
        });
        await tester.tap(find.byTooltip('鎖定'));
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '繼續草稿');
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, '日期（YYYY-MM-DD）'),
              )
              .controller!
              .text,
          '2023-02-29',
        );
        await input(tester, '日期（YYYY-MM-DD）', '2024-02-28');
        await leapDay();
        // Observe the actual saved state before bypassing the UI to read the
        // engine. The engine intentionally rejects reads during a draft write.
        await tester.scrollUntilVisible(
          find.byKey(const Key('draft-status')).hitTestable(),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        for (var i = 0; i < 600; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
          final status = tester.widget<Text>(
            find.byKey(const Key('draft-status')),
          );
          if (status.data == '草稿已加密保存；尚未影響餘額。') break;
        }
        expect(find.text('草稿已加密保存；尚未影響餘額。'), findsOneWidget);
        await tester.runAsync(() async {
          expect((await engine.entryDraft())!.fields.date, '2024-02-29');
          expect(await engine.entries(), hasLength(1));
        });
        await button('儲存收支');
        await tester.runAsync(() async {
          expect((await engine.entries()).map((e) => e.date.toString()), [
            '2024-02-29',
            '2024-02-29',
          ]);
          expect(
            (await engine.accounts()).single.balance.minorUnits,
            BigInt.from(8750),
          );
        });
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await closeEngine(tester, engine);
        deleteSynthetic(work, root);
      }
    },
  );
}
