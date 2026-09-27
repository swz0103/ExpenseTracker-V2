import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/platform_services.dart';
import 'package:expense_preview/preview_engine.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final class Documents implements BackupDocuments {
  String? saved;
  @override
  Future<bool> save(String encrypted) async {
    saved = encrypted;
    return true;
  }

  @override
  Future<String?> open() async => saved;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 600; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
  }
  throw StateError('UI operation did not finish');
}

Future<void> tap(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  await tester.runAsync(() => tester.tap(target));
  await tester.pump();
  await settle(tester);
}

Future<void> input(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
}

Future<void> closeEngine(WidgetTester tester, PreviewEngine engine) async {
  var done = false;
  Object? failure;
  await tester.runAsync(() async {
    engine.lock().then(
      (_) => done = true,
      onError: (Object error) {
        failure = error;
        done = true;
      },
    );
  });
  for (var i = 0; !done && i < 600; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
  if (failure != null) throw failure!;
  if (!done) throw StateError('Session did not close');
}

void main() {
  testWidgets(
    'old V2 App requests explicit upgrade and preserves balance after confirmation',
    (tester) async {
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('upgrade-');
      final vault = MemoryVault();
      var engine = engineAt(work, vault, schemaVersion: 3);
      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          await engine.lock();
        });
        engine = engineAt(work, vault);
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        expect(find.text('更新帳本'), findsOneWidget);
        expect(engine.isUnlocked, isFalse);
        expect(Directory('${work.path}/upgrade-backups').existsSync(), isFalse);
        await tap(tester, '稍後再更新');
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '備份並更新');
        expect(find.text('我的帳本'), findsOneWidget);
        expect(find.text('管理分類'), findsOneWidget);
        expect(find.byType(Card), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await closeEngine(tester, engine);
        await tester.pumpWidget(const SizedBox());
        if (!work.absolute.path.startsWith(
          '${root.absolute.path}${Platform.pathSeparator}',
        )) {
          throw StateError('unsafe cleanup');
        }
        work.deleteSync(recursive: true);
      }
    },
  );

  testWidgets(
    'category creation, classified posting, rename and archive retain visible history on small screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('category-');
      final engine = engineAt(work, MemoryVault());
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
        await tap(tester, '管理分類');
        await tap(tester, '新增分類');
        expect(find.byKey(const Key('category-message')), findsOneWidget);
        await input(tester, '分類名稱', '午餐');
        await tap(tester, '新增分類');
        await tap(tester, '返回帳本');
        await tap(tester, '記一筆');
        await input(tester, '金額（正數）', '25.50');
        await input(tester, '日期（YYYY-MM-DD）', '2026-09-27');
        await tester.ensureVisible(
          find.byKey(const ValueKey('posting-category-false')),
        );
        await tester.tap(find.byKey(const ValueKey('posting-category-false')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('午餐').last);
        await tester.pumpAndSettle();
        await tap(tester, '儲存收支');
        expect(find.text('TWD 74.50'), findsOneWidget);
        expect(find.text('2026-09-27 · 午餐'), findsOneWidget);
        await tap(tester, '管理分類');
        await tester.ensureVisible(find.byTooltip('操作 午餐'));
        await tester.tap(find.byTooltip('操作 午餐'));
        await tester.pumpAndSettle();
        await tap(tester, '改名');
        await input(tester, '新的分類名稱', '餐食');
        await tap(tester, '儲存名稱');
        await tester.ensureVisible(find.byTooltip('操作 餐食'));
        await tester.tap(find.byTooltip('操作 餐食'));
        await tester.pumpAndSettle();
        await tap(tester, '封存');
        await tap(tester, '返回帳本');
        expect(find.text('2026-09-27 · 餐食（已封存）'), findsOneWidget);
        await tap(tester, '記一筆');
        final field = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('posting-category-false')),
        );
        // Only the neutral unclassified choice remains for new transactions.
        expect(field.initialValue, '');
        await tester.ensureVisible(
          find.byKey(const ValueKey('posting-category-false')),
        );
        await tester.tap(find.byKey(const ValueKey('posting-category-false')));
        await tester.pumpAndSettle();
        expect(find.text('餐食（已封存）'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await closeEngine(tester, engine);
        await tester.pumpWidget(const SizedBox());
        if (!work.absolute.path.startsWith(
          '${root.absolute.path}${Platform.pathSeparator}',
        )) {
          throw StateError('unsafe cleanup');
        }
        work.deleteSync(recursive: true);
      }
    },
  );

  testWidgets(
    'setup, account, expense, lock and unlock keep actual amounts on small screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('case-');
      final engine = engineAt(work, MemoryVault());
      try {
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '設定密碼（至少 12 個字元）', password);
        await input(tester, '再次輸入密碼', password);
        await tap(tester, '產生救援文字');
        expect(find.text('保存救援文字'), findsOneWidget);
        final finish = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '完成設定'),
        );
        expect(finish.onPressed, isNull);
        await tap(tester, '我已另外保存救援文字');
        await tap(tester, '完成設定');
        expect(find.text('我的帳本'), findsOneWidget);
        await tap(tester, '新增帳戶');
        await input(tester, '帳戶名稱', '每日現金');
        await input(tester, '期初餘額', '1000');
        await input(tester, '起始日期（YYYY-MM-DD）', '2026-01-01');
        await tap(tester, '建立帳戶');
        expect(
          find.descendant(
            of: find.byType(Card),
            matching: find.text('TWD 1000.00'),
          ),
          findsOneWidget,
        );
        await tap(tester, '記一筆');
        await input(tester, '金額（正數）', '25.50');
        await input(tester, '日期（YYYY-MM-DD）', '2026-09-27');
        await tap(tester, '儲存收支');
        expect(find.text('TWD 974.50'), findsOneWidget);
        expect(find.text('TWD -25.50'), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        await settle(tester);
        expect(find.text('解鎖帳本'), findsOneWidget);
        expect(find.text('每日現金'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        expect(find.text('TWD 974.50'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await closeEngine(tester, engine);
        await tester.pumpWidget(const SizedBox());
        if (!work.absolute.path.startsWith(
          '${root.absolute.path}${Platform.pathSeparator}',
        )) {
          throw StateError('unsafe cleanup');
        }
        work.deleteSync(recursive: true);
      }
    },
  );
  testWidgets(
    'invalid form stays editable and duplicate taps never duplicate an account',
    (tester) async {
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('case-');
      final engine = engineAt(work, MemoryVault());
      try {
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '設定密碼（至少 12 個字元）', password);
        await input(tester, '再次輸入密碼', password);
        await tap(tester, '產生救援文字');
        await tap(tester, '我已另外保存救援文字');
        await tap(tester, '完成設定');
        await tap(tester, '新增帳戶');
        await tap(tester, '建立帳戶');
        expect(find.byKey(const Key('message')), findsOneWidget);
        await input(tester, '帳戶名稱', '銀行');
        await tester.ensureVisible(find.text('建立帳戶'));
        await tester.runAsync(() async {
          await tester.tap(find.text('建立帳戶'));
          await tester.tap(find.text('建立帳戶'));
        });
        await tester.pump();
        await settle(tester);
        expect(find.byType(Card), findsOneWidget);
        expect(find.text('銀行'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await closeEngine(tester, engine);
        await tester.pumpWidget(const SizedBox());
        if (!work.absolute.path.startsWith(
          '${root.absolute.path}${Platform.pathSeparator}',
        )) {
          throw StateError('unsafe cleanup');
        }
        work.deleteSync(recursive: true);
      }
    },
  );
}
