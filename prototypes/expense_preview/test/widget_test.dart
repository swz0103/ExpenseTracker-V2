import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/platform_services.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:categories/categories.dart';
import 'package:data_exchange/data_exchange.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final class Documents implements BackupDocuments {
  String? saved;
  VoidCallback? onOpen;
  String? simple;
  VoidCallback? onChooseSimple;
  String? simpleExport;
  String? selectedExportFormat;
  VoidCallback? onChooseSimpleExport;
  @override
  Future<bool> save(String encrypted) async {
    saved = encrypted;
    return true;
  }

  @override
  Future<String?> open() async {
    onOpen?.call();
    return saved;
  }

  @override
  Future<bool> chooseSimpleImport() async {
    onChooseSimple?.call();
    return simple != null;
  }

  @override
  Future<String?> readSimpleImport() async {
    final selected = simple;
    simple = null;
    return selected;
  }

  @override
  Future<void> discardSimpleImport() async => simple = null;

  @override
  Future<bool> chooseSimpleExport(String format) async {
    selectedExportFormat = format;
    onChooseSimpleExport?.call();
    return true;
  }

  @override
  Future<bool> writeSimpleExport(String contents) async {
    simpleExport = contents;
    selectedExportFormat = null;
    return true;
  }

  @override
  Future<void> discardSimpleExport() async => selectedExportFormat = null;
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

Future<void> waitForImportDialog(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (find.text('確認匯入').evaluate().isNotEmpty) return;
  }
  throw StateError('Import confirmation did not open');
}

Future<void> waitForExportDialog(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (find.text('確認儲存未加密交換檔').evaluate().isNotEmpty) return;
  }
  throw StateError('Export confirmation did not open');
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
    'tags can be created selected merged and archived while old transaction remains traceable',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('tags-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 6);
      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          await engine.createTag(
            OperationKey(engine.workspace, OperationId(PublicId.generate())),
            PublicId.generate(),
            '旅行',
          );
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '管理標籤');
        await input(tester, '標籤名稱', '出差');
        await tap(tester, '新增標籤');
        await tap(tester, '返回帳本');
        await tap(tester, '記一筆');
        await input(tester, '金額（正數）', '10');
        await input(tester, '日期（YYYY-MM-DD）', '2026-09-27');
        await tap(tester, '出差');
        await tap(tester, '旅行');
        await tester.scrollUntilVisible(
          find.text('儲存收支').hitTestable(),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('儲存收支').hitTestable(), findsOneWidget);
        await tap(tester, '儲存收支');
        expect(find.text('TWD 90.00'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.textContaining('#出差'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.textContaining('#出差'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('記一筆'),
          -180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
        await tester.pumpAndSettle();
        expect(find.text('記一筆').hitTestable(), findsOneWidget);
        await tap(tester, '記一筆');
        await tester.scrollUntilVisible(
          find.text('返回帳本'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.byType(FilterChip), findsNWidgets(2));
        expect(
          tester
              .widgetList<FilterChip>(find.byType(FilterChip))
              .every((c) => !c.selected),
          isTrue,
        );
        await tap(tester, '返回帳本');
        await tap(tester, '管理標籤');
        await tester.ensureVisible(find.byTooltip('操作 出差'));
        await tester.tap(find.byTooltip('操作 出差'));
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
        final dropdown = find.byType(DropdownButtonFormField<String>);
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('旅行').last);
        await tester.pumpAndSettle();
        await tap(tester, '確認合併並保留歷史');
        await tap(tester, '返回帳本');
        await tester.scrollUntilVisible(
          find.textContaining('#出差（已合併至 旅行）'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.textContaining('#出差（已合併至 旅行）'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('管理標籤'),
          -180,
          scrollable: find.byType(Scrollable).first,
        );
        await tap(tester, '管理標籤');
        await tester.ensureVisible(find.byTooltip('操作 旅行'));
        await tester.tap(find.byTooltip('操作 旅行'));
        await tester.pumpAndSettle();
        await tap(tester, '封存');
        await tap(tester, '返回帳本');
        await tap(tester, '記一筆');
        await tester.scrollUntilVisible(
          find.text('返回帳本').hitTestable(),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.byType(FilterChip), findsNothing);
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
  testWidgets(
    'category move, cancel and explicit merge preserve a clear selection',
    (tester) async {
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('management-');
      final engine = engineAt(work, MemoryVault());
      final parent = PublicId.generate(),
          child = PublicId.generate(),
          target = PublicId.generate();
      try {
        await tester.runAsync(() async {
          await setup(engine);
          OperationKey op() =>
              OperationKey(engine.workspace, OperationId(PublicId.generate()));
          await engine.createCategory(op(), parent, '工作', CategoryKind.income);
          await engine.createCategory(
            op(),
            child,
            '薪資',
            CategoryKind.income,
            parentId: parent,
          );
          await engine.createCategory(
            op(),
            target,
            '收入整併',
            CategoryKind.income,
          );
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '管理分類');
        Future<void> menu(String action) async {
          final target = find.byTooltip('操作 薪資');
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          expect(target.hitTestable(), findsOneWidget);
          await tester.tap(target.hitTestable());
          await tester.pumpAndSettle();
          await tap(tester, action);
        }

        await menu('移動');
        await tap(tester, '取消編輯');
        expect(find.text('分類名稱'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await menu('移動');
        await tester.ensureVisible(find.byKey(ValueKey('move-$child')));
        await tester.tap(find.byKey(ValueKey('move-$child')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('無（第一層）').last);
        await tester.pumpAndSettle();
        await tap(tester, '確認移動');
        await menu('合併至…');
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, '確認合併並保留歷史'),
              )
              .onPressed,
          isNull,
        );
        await tester.ensureVisible(find.byKey(ValueKey('merge-$child')));
        await tester.tap(find.byKey(ValueKey('merge-$child')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('收入整併').last);
        await tester.pumpAndSettle();
        await tap(tester, '確認合併並保留歷史');
        expect(find.text('薪資（已合併至 收入整併）'), findsOneWidget);
        expect(find.byTooltip('操作 薪資'), findsNothing);
        await tester.runAsync(() async {
          final catalog = await engine.categories();
          expect(catalog.get(child).parentId, isNull);
          expect(catalog.resolve(child).id, target);
        });
        expect(tester.takeException(), isNull);
      } finally {
        await closeEngine(tester, engine);
        await tester.pumpWidget(const SizedBox());
        if (!work.resolveSymbolicLinksSync().startsWith(
          '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
        )) {
          throw StateError('unsafe cleanup');
        }
        work.deleteSync(recursive: true);
      }
    },
  );

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
        await tester.scrollUntilVisible(
          find.text('2026-09-27 · 午餐'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('2026-09-27 · 午餐'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('管理分類'),
          -180,
          scrollable: find.byType(Scrollable).first,
        );
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
        await tester.scrollUntilVisible(
          find.text('2026-09-27 · 餐食（已封存）'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('2026-09-27 · 餐食（已封存）'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('記一筆'),
          -180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
        await tester.pumpAndSettle();
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
        await tester.scrollUntilVisible(
          find.text('TWD -25.50'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
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
        expect(find.byKey(const Key('message')).hitTestable(), findsOneWidget);
        await tester.runAsync(() async {
          expect(await engine.accounts(), isEmpty);
          expect(await engine.entries(), isEmpty);
        });
        await input(tester, '帳戶名稱', '銀行');
        await tester.ensureVisible(find.text('建立帳戶'));
        await tester.pumpAndSettle();
        final create = find.text('建立帳戶').hitTestable();
        expect(create, findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(create);
          await tester.tap(create);
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

  testWidgets(
    'simple import picker locks, requires review and explicit confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('simple-import-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 12);
      final docs = Documents();
      try {
        await tester.runAsync(() async {
          await setup(engine);
          final cash = account(engine, name: 'Import target');
          await engine.createAccount(cash, opening(cash));
          docs.simple = SimpleTransactionCodec.encodeJson(
            SimpleTransactionBatch(WorkspaceId(PublicId.generate()), [
              SimpleTransaction(
                sourceRecordId: PublicId.generate(),
                date: BusinessDate(2026, 9, 28),
                kind: PostingKind.income,
                accountId: PublicId.generate(),
                amount: Money.parse(cash.currency, '12.34'),
              ),
            ]),
          );
          await engine.setPrivacyMode(PrivacyMode.hidden);
          await engine.lock();
        });
        final source = SimpleTransactionCodec.decodeJson(docs.simple!)
            .records
            .single
            .accountId;
        docs.onChooseSimple = () => tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: docs),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tester.scrollUntilVisible(
          find.text('匯入簡易收支檔'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tap(tester, '匯入簡易收支檔');
        expect(find.text('解鎖帳本'), findsOneWidget);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '讀取所選檔案');
        expect(find.textContaining('檔案共有 1 筆'), findsOneWidget);
        final mapping = find.byKey(ValueKey('simple-account-${source.value}'));
        await tester.ensureVisible(mapping);
        await tester.tap(mapping);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Import target · TWD').last);
        await tester.pumpAndSettle();
        await tap(tester, '檢查對應與金額');
        await tester.runAsync(() async {
          expect(
            (await engine.accounts()).single.balance.minorUnits,
            BigInt.from(10000),
          );
        });
        if (tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, '確認匯入目前帳本'),
                )
                .onPressed ==
            null) {
          await tester.tap(find.byTooltip('顯示金額'));
          await tester.pump();
          await settle(tester);
        }
        await tester.ensureVisible(find.text('確認匯入目前帳本'));
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, '確認匯入目前帳本'),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.text('確認匯入目前帳本'));
        await waitForImportDialog(tester);
        await tester.tap(find.text('取消'));
        await tester.pump();
        await settle(tester);
        await tester.runAsync(() async {
          expect(
            (await engine.accounts()).single.balance.minorUnits,
            BigInt.from(10000),
          );
        });
        await tester.tap(find.text('確認匯入目前帳本'));
        await waitForImportDialog(tester);
        await tester.tap(find.text('確認匯入'));
        await tester.pump();
        await settle(tester);
        await tester.runAsync(() async {
          expect(
            (await engine.accounts()).single.balance.minorUnits,
            BigInt.from(11234),
          );
        });
        expect(find.textContaining('新增 1 筆'), findsOneWidget);
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
    'simple export locks, discloses omissions and saves only after confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('simple-export-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 12);
      final docs = Documents();
      try {
        await tester.runAsync(() async {
          await setup(engine);
          final cash = account(engine, name: 'Export source');
          await engine.createAccount(cash, opening(cash));
          await engine.post(income(cash));
          await engine.setPrivacyMode(PrivacyMode.hidden);
          await engine.lock();
        });
        docs.onChooseSimpleExport = () => tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: docs),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
      await tester.scrollUntilVisible(
        find.text('匯出簡易收支檔'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tap(tester, '匯出簡易收支檔');
        await tap(tester, '選擇 JSON 儲存位置');
        expect(docs.selectedExportFormat, 'json');
        expect(find.text('解鎖帳本'), findsOneWidget);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '檢查將匯出的交易');
        expect(find.text('將匯出 1 筆普通收支。'), findsOneWidget);
        expect(find.textContaining('略過 1 筆期初'), findsOneWidget);
        final confirm = find.widgetWithText(FilledButton, '確認儲存 JSON 交換檔');
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        await tester.tap(find.byTooltip('顯示金額'));
        await tester.pump();
        await settle(tester);
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await waitForExportDialog(tester);
        await tester.tap(find.text('取消'));
        await tester.pump();
        await settle(tester);
        expect(docs.simpleExport, isNull);
        await tester.tap(confirm);
        await waitForExportDialog(tester);
        await tester.tap(find.text('確認儲存'));
        await tester.pump();
        await settle(tester);
        final exported = SimpleTransactionCodec.decodeJson(docs.simpleExport!);
        expect(exported.records, hasLength(1));
        expect(exported.records.single.amount.minorUnits, BigInt.from(700));
        await tester.runAsync(() async {
          expect(
            (await engine.accounts()).single.balance.minorUnits,
            BigInt.from(10700),
          );
        });
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
