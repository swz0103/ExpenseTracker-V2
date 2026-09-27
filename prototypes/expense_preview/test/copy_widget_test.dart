import 'dart:io';

import 'package:categories/categories.dart';
import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  testWidgets(
    'safe copy needs fresh amount and date, creates a new receipt and retains original metadata',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('copy-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 7);
      late PublicId sourceId, category, tag, merchant, sourceAccount;
      try {
        await tester.runAsync(() async {
          await setup(engine);
          for (var i = 0; i < 2; i++) {
            final item = account(engine);
            await engine.createAccount(item, opening(item));
          }
          final a = (await engine.accounts()).last.account;
          sourceAccount = a.id;
          OperationKey op() =>
              OperationKey(engine.workspace, OperationId(PublicId.generate()));
          category = PublicId.generate();
          tag = PublicId.generate();
          merchant = PublicId.generate();
          await engine.createCategory(
            op(),
            category,
            '薪資',
            CategoryKind.income,
          );
          await engine.createTag(op(), tag, '固定');
          await engine.createMerchant(op(), merchant, '公司');
          final source = Posting.income(
            id: PublicId.generate(),
            operation: op(),
            date: BusinessDate(2026, 1, 2),
            account: ref(a),
            amount: Money.parse(a.currency, '123.45'),
            allocations: [
              Allocation(
                category,
                Money.parse(a.currency, '123.45'),
                expectedCategoryVersion: 1,
              ),
            ],
          );
          sourceId = source.id;
          await engine.post(
            source,
            tags: [TagSelection(tag, 1)],
            merchant: MerchantSelection(merchant, 1),
          );
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        final actions = find.byKey(ValueKey('entry-actions-$sourceId'));
        await tester.ensureVisible(actions);
        await tester.tap(actions);
        await tester.pumpAndSettle();
        await tap(tester, '再記一筆類似交易');
        await tester.pumpAndSettle();
        String fieldValue(String label) => tester
            .widget<TextField>(find.widgetWithText(TextField, label))
            .controller!
            .text;
        expect(
          tester
              .widget<DropdownButtonFormField<PublicId>>(
                find.byType(DropdownButtonFormField<PublicId>),
              )
              .initialValue,
          sourceAccount,
        );
        expect(fieldValue('金額（正數）'), isEmpty);
        expect(fieldValue('日期（YYYY-MM-DD）'), isEmpty);
        expect(
          tester
              .widget<FilterChip>(find.widgetWithText(FilterChip, '固定'))
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byKey(const ValueKey('merchant-choice-')),
              )
              .initialValue,
          merchant.value,
        );
        await tester.scrollUntilVisible(
          find.text('儲存收支'),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tap(tester, '儲存收支');
        await tester.runAsync(
          () async => expect(await engine.entries(), hasLength(3)),
        );
        await tester.scrollUntilVisible(
          find.widgetWithText(TextField, '金額（正數）'),
          -220,
          scrollable: find.byType(Scrollable).first,
        );
        await input(tester, '金額（正數）', '10');
        await input(tester, '日期（YYYY-MM-DD）', '2026-09-27');
        await tester.scrollUntilVisible(
          find.text('儲存收支'),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tap(tester, '儲存收支');
        expect(find.text('TWD 233.45'), findsOneWidget);
        await tester.runAsync(() async {
          final rows = await engine.entries();
          expect(rows, hasLength(4));
          final copied = rows.firstWhere(
            (r) => r.id != sourceId && r.kind == PostingKind.income,
          );
          expect(copied.accountId, sourceAccount);
          expect(copied.amount.minorUnits, BigInt.from(1000));
          expect(copied.date.toString(), '2026-09-27');
          expect(
            (await engine.allocations(copied.id)).single.categoryId,
            category,
          );
          expect((await engine.tagsFor(copied.id)).single.id, tag);
          expect((await engine.merchantFor(copied.id))!.id, merchant);
          expect(
            rows.firstWhere((r) => r.id == sourceId).amount.minorUnits,
            BigInt.from(12345),
          );
        });
        await tap(tester, '記一筆');
        expect(
          tester
              .widget<FilterChip>(find.widgetWithText(FilterChip, '固定'))
              .selected,
          isFalse,
        );
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byKey(const ValueKey('merchant-choice-')),
              )
              .initialValue,
          '',
        );
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
