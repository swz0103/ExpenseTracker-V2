import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:expense_preview/transfer_summary.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  testWidgets(
    'transfer selection, raw fee draft restart, invalid input and submit reflect both accounts and fee',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('transfer-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 8);
      Future<void> button(String label) async {
        await tester.scrollUntilVisible(
          find.text(label).hitTestable(),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tap(tester, label);
      }

      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine, name: '轉出現金'),
              b = account(engine, name: '轉入銀行');
          await engine.createAccount(a, opening(a));
          await engine.createAccount(b, opening(b));
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '同幣轉帳');
        await input(tester, '金額（正數）', '20');
        await button('儲存轉帳');
        expect(find.text('請選擇可用的轉出與轉入帳戶。').hitTestable(), findsOneWidget);
        final picker = find.widgetWithText(
          DropdownButtonFormField<PublicId>,
          '轉入帳戶',
        );
        await tester.ensureVisible(picker);
        await tester.pumpAndSettle();
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(find.text('轉入銀行').last);
        await tester.pumpAndSettle();
        await input(tester, '金額（正數）', '20');
        await input(tester, '手續費（可為 0）', '1+');
        await tester.tap(find.byTooltip('鎖定'));
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '繼續草稿');
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '手續費（可為 0）'))
              .controller!
              .text,
          '1+',
        );
        await input(tester, '手續費（可為 0）', '-1');
        await button('儲存轉帳');
        await tester.runAsync(() async {
          expect(await engine.entries(), hasLength(2));
          expect((await engine.entryDraft())!.fields.transfer, isTrue);
        });
        await input(tester, '手續費（可為 0）', '1.25');
        await button('儲存轉帳');
        await tester.runAsync(() async {
          final rows = await engine.accounts();
          expect(
            rows
                .singleWhere((a) => a.account.name == '轉出現金')
                .balance
                .minorUnits,
            BigInt.from(7875),
          );
          expect(
            rows
                .singleWhere((a) => a.account.name == '轉入銀行')
                .balance
                .minorUnits,
            BigInt.from(12000),
          );
          expect(await engine.entries(), hasLength(3));
          expect(await engine.entryDraft(), isNull);
        });
        await tester.scrollUntilVisible(
          find.byType(TransferSummary),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('轉帳 · 轉出現金 → 轉入銀行'), findsOneWidget);
        expect(find.text('TWD 21.25'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await closeEngine(tester, engine);
        deleteSynthetic(work, root);
      }
    },
  );
  testWidgets(
    'transfer narrow large-font summary masks every amount and accessibility label',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      final c = Currency('TWD', 2);
      final entry = LedgerEntry(
        PublicId.generate(),
        BusinessDate(2026, 9, 27),
        PostingKind.transfer,
        PublicId.generate(),
        Money.parse(c, '-20'),
        destinationId: PublicId.generate(),
        fee: Money.parse(c, '1.25'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3.2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: TransferSummary(
                  entry: entry,
                  source: '很長的來源帳戶名稱',
                  destination: '很長的轉入銀行名稱',
                  privacy: PrivacyMode.hidden,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('21.25'), findsNothing);
      expect(find.textContaining('1.25'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('21.25|1.25|20.00')), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
