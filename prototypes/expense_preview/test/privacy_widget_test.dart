import 'dart:io';

import 'package:expense_preview/main.dart';
import 'package:expense_preview/money_view.dart';
import 'package:expense_preview/privacy_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  test('money presentation keeps integer precision and never formats hidden financial values', () {
    final cases = [
      (
        Money(Currency('TWD', 2), BigInt.parse('9223372036854775807')),
        'TWD 92233720368547758.07',
      ),
      (Money(Currency('JPY', 0), BigInt.from(-123)), 'JPY -123'),
      (Money(Currency('USD', 2), BigInt.from(1)), 'USD 0.01'),
    ];
    for (final (money, text) in cases) {
      expect(
        presentMoney(money, PrivacyMode.visible, MoneyKind.transaction).text,
        text,
      );
      expect(presentMoney(money, PrivacyMode.hidden, MoneyKind.transaction), (
        text: '••••',
        label: '交易金額已隱藏',
      ));
    }
  });
  testWidgets('hidden money is absent from pixels and accessible labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final money = Money.parse(Currency('TWD', 2), '12345.67');
      for (final mode in [PrivacyMode.visible, PrivacyMode.hidden]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MoneyView(
                money: money,
                privacy: mode,
                kind: MoneyKind.balance,
              ),
            ),
          ),
        );
        if (mode == PrivacyMode.hidden) {
          expect(find.text('TWD 12345.67'), findsNothing);
          expect(find.bySemanticsLabel(RegExp('12345')), findsNothing);
          expect(find.bySemanticsLabel('帳戶餘額已隱藏'), findsOneWidget);
        } else {
          expect(find.bySemanticsLabel('帳戶餘額 TWD 12345.67'), findsOneWidget);
        }
      }
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
    'long names and exact large amounts fit narrow screens and large fonts with labeled targets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        for (final width in [320.0, 600.0]) {
          for (final scale in [1.0, 2.0, 3.2]) {
            tester.view.physicalSize = Size(width, 1000);
            await tester.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 1000),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      key: ValueKey('$width-$scale'),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: FinancialSummary(
                          title: '很長的帳戶名稱' * 10,
                          subtitle: '分類／商家／標籤名稱' * 8,
                          money: Money(
                            Currency('TWD', 2),
                            BigInt.parse('9223372036854775807'),
                          ),
                          privacy: PrivacyMode.visible,
                          kind: MoneyKind.balance,
                          moneyKey: const Key('amount'),
                          action: IconButton(
                            key: const Key('action'),
                            tooltip: '交易操作',
                            onPressed: () {},
                            icon: const Icon(Icons.more_vert),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.ensureVisible(find.byKey(const Key('action')));
            await tester.pump();
            expect(
              tester.takeException(),
              null,
              reason: 'width=$width scale=$scale',
            );
            expect(find.text('TWD 92233720368547758.07'), findsOneWidget);
            expect(
              tester.getSize(find.byKey(const Key('action'))).height,
              greaterThanOrEqualTo(48),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
          }
        }
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets(
    'App privacy persists across lock and cannot reveal when preference saving fails',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('privacy-');
      final vault = MemoryVault(), documents = Documents();
      final engine = engineAt(work, vault, schemaVersion: 7);
      Future<void> eye(String label) async {
        await tester.runAsync(() => tester.tap(find.byTooltip(label)));
        await tester.pump();
        await settle(tester);
      }

      try {
        await tester.runAsync(() async {
          await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: documents),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        expect(find.text('TWD 100.00'), findsWidgets);
        await eye('隱藏金額');
        expect(find.text('TWD 100.00'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('100.00')), findsNothing);
        await tester.runAsync(() => tester.tap(find.byTooltip('鎖定')));
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        expect(find.text('TWD 100.00'), findsNothing);
        vault.failWrites = true;
        await eye('顯示金額');
        expect(find.text('TWD 100.00'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('100.00')), findsNothing);
        expect(find.text('遮罩設定尚未保存，本次開啟期間維持隱藏。請稍後重試。'), findsOneWidget);
        vault.failWrites = false;
        await eye('顯示金額');
        expect(find.text('TWD 100.00'), findsWidgets);
        vault.failWrites = true;
        await eye('隱藏金額');
        expect(find.text('TWD 100.00'), findsNothing);
        vault.failWrites = false;
        await tap(tester, '記一筆');
        await tester.scrollUntilVisible(
          find.text('返回帳本'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tap(tester, '返回帳本');
        expect(find.text('TWD 100.00'), findsNothing);
        await tester.runAsync(() => tester.tap(find.byTooltip('鎖定')));
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        expect(find.text('TWD 100.00'), findsNothing);
        await eye('顯示金額');
        expect(find.text('TWD 100.00'), findsWidgets);
        await eye('隱藏金額');
        await tap(tester, '記一筆');
        await input(tester, '金額（正數）', '12');
        await tap(tester, '儲存收支');
        expect(find.text('TWD 88.00'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('88.00|-12.00')), findsNothing);
        await eye('顯示金額');
        expect(find.text('TWD 88.00'), findsOneWidget);
      } finally {
        semantics.dispose();
        vault.failWrites = false;
        await tester.pumpWidget(const SizedBox());
        await closeEngine(tester, engine);
        deleteSynthetic(work, root);
      }
    },
  );
}
