import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  testWidgets(
    'merchant aliases require choice and preserve history after explicit merge',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('merchants-');
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
        await tap(tester, '管理商家');
        for (final name in ['商店甲', '商店乙']) {
          await input(tester, '商家名稱', name);
          await tap(tester, '新增商家');
          await tester.ensureVisible(find.byTooltip('操作 $name'));
          await tester.tap(find.byTooltip('操作 $name'));
          await tester.pumpAndSettle();
          await tap(tester, '管理別名');
          await input(tester, '新增別名', 'SHOP');
          await tap(tester, '儲存別名');
        }
        await tap(tester, '返回帳本');
        await tap(tester, '記一筆');
        await input(tester, '金額（正數）', '10');
        await input(tester, '日期（YYYY-MM-DD）', '2026-09-27');
        await input(tester, '商家名稱或別名（選填）', 'shop');
        await tester.pumpAndSettle();
        expect(find.text('找到 2 個候選，請確認選擇。'), findsOneWidget);
        final selector = find.byKey(const ValueKey('merchant-choice-shop'));
        expect(
          tester.widget<DropdownButtonFormField<String>>(selector).initialValue,
          '',
        );
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text('商店甲').last);
        await tester.pumpAndSettle();
        await tap(tester, '儲存收支');
        expect(find.text('TWD 90.00'), findsOneWidget);
        expect(find.textContaining('2026-09-27 · 未分類 · 商店甲'), findsOneWidget);
        await tap(tester, '記一筆');
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byKey(const ValueKey('merchant-choice-')),
              )
              .initialValue,
          '',
        );
        await input(tester, '商家名稱或別名（選填）', 'x\u0000');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tap(tester, '返回帳本');
        await tap(tester, '管理商家');
        await tester.ensureVisible(find.byTooltip('操作 商店甲'));
        await tester.tap(find.byTooltip('操作 商店甲'));
        await tester.pumpAndSettle();
        await tap(tester, '合併至…');
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, '確認合併並保留歷史'),
              )
              .onPressed,
          isNull,
        );
        final target = find.byType(DropdownButtonFormField<String>);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        await tester.tap(find.text('商店乙').last);
        await tester.pumpAndSettle();
        await tap(tester, '確認合併並保留歷史');
        await tap(tester, '返回帳本');
        await tester.scrollUntilVisible(
          find.textContaining('商店甲（已合併至 商店乙）'),
          180,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
        expect(find.textContaining('商店甲（已合併至 商店乙）'), findsOneWidget);
        await tester.runAsync(() async {
          final catalog = await engine.merchants();
          expect(catalog.candidates('SHOP').single.name, '商店乙');
          final row = (await engine.entries()).firstWhere(
            (e) => e.amount.minorUnits.isNegative,
          );
          expect((await engine.merchantFor(row.id))!.version, 2);
        });
        expect(tester.takeException(), isNull);
      } finally {
        await closeEngine(tester, engine);
        await tester.pumpWidget(const SizedBox());
        if (!work.resolveSymbolicLinksSync().startsWith(
          '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
        )) {
          throw StateError('Unsafe cleanup');
        }
        work.deleteSync(recursive: true);
      }
    },
  );
}
