import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:expense_preview/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, closeEngine, input, settle, tap;

void main() {
  testWidgets(
    'asset summary stays per-currency after transfer, masks and locks',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory('.dart_tool/widget-tests')
        ..createSync(recursive: true);
      final work = root.createTempSync('asset-report-');
      final engine = engineAt(work, MemoryVault(), schemaVersion: 12);
      try {
        await tester.runAsync(() async {
          await setup(engine);
          final cash = account(engine);
          final usd = Account.open(
            id: PublicId.generate(),
            workspace: engine.workspace,
            name: '美元銀行',
            kind: AccountKind.bank,
            currency: Currency('USD', 2),
            openedOn: cash.openedOn,
          );
          final excluded = Account.open(
            id: PublicId.generate(),
            workspace: engine.workspace,
            name: '不計入帳戶',
            kind: AccountKind.cash,
            currency: cash.currency,
            openedOn: cash.openedOn,
            includeInNetWorth: false,
          );
          for (final row in [cash, usd, excluded]) {
            await engine.createAccount(row, opening(row));
          }
          await engine.post(
            Posting.transfer(
              id: PublicId.generate(),
              operation: OperationKey(
                engine.workspace,
                OperationId(PublicId.generate()),
              ),
              date: BusinessDate(2026, 9, 1),
              source: ref(cash),
              destination: ref(usd),
              principal: Money.parse(cash.currency, '20'),
              received: Money.parse(usd.currency, '1'),
              fee: Money.parse(cash.currency, '2'),
            ),
          );
          final saved = await engine.accounts();
          expect(
            saved.where((row) => row.account.includeInNetWorth),
            hasLength(2),
          );
          expect(
            saved.where((row) => !row.account.includeInNetWorth),
            hasLength(1),
          );
          await engine.lock();
        });
        await tester.pumpWidget(
          PreviewApp(engine: Future.value(engine), documents: Documents()),
        );
        await settle(tester);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tester.scrollUntilVisible(
          find.text('資產摘要'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('資產摘要'), findsOneWidget);
        expect(tester.takeException(), null);
        expect(find.text('沒有納入摘要的帳戶。'), findsNothing);
        expect(find.text('帳戶合計超過可表示範圍，暫不顯示資產摘要；個別帳戶餘額仍保留。'), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const Key('asset-total-TWD')),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(const Key('asset-total-TWD')), findsOneWidget);
        expect(find.text('TWD 78.00'), findsWidgets);
        await tester.scrollUntilVisible(
          find.byKey(const Key('asset-total-USD')),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(const Key('asset-total-USD')), findsOneWidget);
        expect(find.text('USD 101.00'), findsWidgets);
        await tester.scrollUntilVisible(
          find.text('另有 1 個帳戶設定為不納入摘要。'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('另有 1 個帳戶設定為不納入摘要。'), findsOneWidget);
        await tester.tap(find.byTooltip('隱藏金額'));
        await settle(tester);
        expect(find.text('TWD 78.00'), findsNothing);
        expect(find.text('USD 101.00'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await settle(tester);
        expect(find.text('資產摘要'), findsNothing);
        expect(tester.takeException(), null);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await closeEngine(tester, engine);
        deleteSynthetic(work, root);
      }
    },
  );
}
