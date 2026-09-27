import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  testWidgets(
    'opening and expense calculations are explicit, draft resumes raw expression and invalid calculation cannot post',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('calculator-');
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

      Future<void> calculate() async {
        await tester.ensureVisible(find.byTooltip('計算金額'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('計算金額'));
        await tester.pump();
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
        await input(tester, '帳戶名稱', '計算現金');
        await input(tester, '期初餘額', '10+90');
        await calculate();
        expect(find.text('計算結果：TWD 100.00'), findsOneWidget);
        await button('套用結果');
        await input(tester, '起始日期（YYYY-MM-DD）', '2026-01-01');
        await button('建立帳戶');
        expect(find.text('TWD 100.00'), findsWidgets);
        await tap(tester, '記一筆');
        await input(tester, '金額（正數）', '1/0');
        await calculate();
        expect(find.text('不能除以零，請修改算式。'), findsOneWidget);
        expect(find.text('套用結果'), findsNothing);
        await input(tester, '金額（正數）', '12+3*2');
        await tester.tap(find.byTooltip('鎖定'));
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '繼續草稿');
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '金額（正數）'))
              .controller!
              .text,
          '12+3*2',
        );
        await calculate();
        expect(find.text('計算結果：TWD 18.00'), findsOneWidget);
        await tester.runAsync(
          () async => expect(await engine.entries(), hasLength(1)),
        );
        await button('套用結果');
        await button('儲存收支');
        expect(find.text('TWD 82.00'), findsOneWidget);
        await tester.runAsync(
          () async => expect(await engine.entries(), hasLength(2)),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await closeEngine(tester, engine);
        deleteSynthetic(work, root);
      }
    },
  );
}
