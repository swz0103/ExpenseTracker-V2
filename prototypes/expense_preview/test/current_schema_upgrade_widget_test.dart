import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/main.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';
import 'widget_test.dart' show Documents, settle, tap, input, closeEngine;

void main() {
  testWidgets(
    'V2 schema 12 opens current schema 24 only after explicit safety-backed upgrade',
    (tester) async {
      expect(currentPreviewSchemaVersion, 24);
      final root = Directory('.dart_tool/current-schema-upgrade-widget')
        ..createSync(recursive: true);
      final work = root.createTempSync('case-');
      final vault = MemoryVault();
      var engine = engineAt(work, vault, schemaVersion: 12);
      late PublicId expenseId;
      late String recoveryKey;
      late List<int> oldSnapshot;
      try {
        await tester.runAsync(() async {
          recoveryKey = await setup(engine);
          final a = account(engine);
          await engine.createAccount(a, opening(a));
          final expense = Posting.expense(
            id: PublicId.generate(),
            operation: OperationKey(
              engine.workspace,
              OperationId(PublicId.generate()),
            ),
            date: BusinessDate(2026, 9, 28),
            account: ref(a),
            amount: Money.parse(a.currency, '10'),
          );
          expenseId = expense.id;
          await engine.post(expense);
          await engine.saveEntryDraft(
            EntryFields(
              income: false,
              amount: '',
              date: '',
              noteOf: expense.id,
              noteRevision: 0,
              noteText: 'old V2 receipt',
            ),
          );
          await engine.submitEntryDraft();
          oldSnapshot = await EnvelopeCodec().openWithPassword(
            await engine.exportBackup(),
            password,
          );
          await engine.lock();
        });
        engine = engineAt(
          work,
          vault,
          schemaVersion: currentPreviewSchemaVersion,
        );
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
        expect(find.text('解鎖帳本'), findsOneWidget);
        await input(tester, '密碼', password);
        await tap(tester, '解鎖');
        await tap(tester, '備份並更新', maxPolls: 12000);
        expect(find.text('我的帳本'), findsOneWidget);
        expect(engine.capabilities.corrections, isTrue);
        expect(engine.capabilities.tombstones, isTrue);
        expect(engine.capabilities.budgets, isTrue);
        expect(engine.capabilities.recurring, isTrue);
        expect(engine.capabilities.creditCards, isTrue);
        expect(engine.capabilities.cardStatements, isTrue);
        expect(engine.capabilities.cardAuthorizations, isTrue);
        expect(engine.capabilities.installments, isTrue);
        expect(engine.capabilities.investments, isTrue);
        expect(engine.capabilities.investmentSales, isTrue);
        expect(engine.capabilities.investmentDividends, isTrue);
        expect(engine.capabilities.investmentSplits, isTrue);
        await tester.runAsync(() async {
          expect(
            (await engine.accounts()).single.balance,
            Money.parse(Currency('TWD', 2), '90'),
          );
          expect((await engine.entryNote(expenseId)).text, 'old V2 receipt');
          final copies = Directory('${work.path}/upgrade-backups')
              .listSync()
              .whereType<File>()
              .toList();
          expect(copies, hasLength(12));
          final schemas = <int>{};
          for (final copy in copies) {
            final encrypted = copy.readAsStringSync();
            final fromPassword = await EnvelopeCodec().openWithPassword(
              encrypted,
              password,
            );
            final fromRecovery = await EnvelopeCodec().openWithRecovery(
              encrypted,
              recoveryKey,
            );
            expect(fromRecovery, fromPassword);
            final schema =
                (jsonDecode(utf8.decode(fromPassword)) as Map)['schema'] as int;
            schemas.add(schema);
            if (schema == 12) expect(fromPassword, oldSnapshot);
          }
          expect(schemas, {12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23});
          expect(await engine.exportBackup(), isNotEmpty);
        });
        final actions = find.byKey(ValueKey('entry-actions-$expenseId'));
        await tester.scrollUntilVisible(
          actions,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(actions);
        await tester.pumpAndSettle();
        await tester.tap(actions);
        await tester.pumpAndSettle();
        expect(find.text('更正交易'), findsOneWidget);
        expect(find.text('刪除交易'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await closeEngine(tester, engine);
        await tester.pumpWidget(const SizedBox());
        // SQLCipher's native Windows worker can keep a directory handle until
        // the test process exits. CI/Linux still removes the synthetic case.
        if (!Platform.isWindows) deleteSynthetic(work, root);
      }
    },
  );

  test('schema22 investments survive an explicit opt-in upgrade to schema24 and both restores', () async {
    final root = Directory('.dart_tool/current-schema-investment-upgrade')
      ..createSync(recursive: true);
    final work = root.createTempSync('source-');
    final vault = MemoryVault();
    var engine = engineAt(work, vault, schemaVersion: 22);
    try {
      final recoveryKey = await setup(engine);
      final cash = account(engine, name: 'Synthetic investment cash');
      await engine.createAccount(cash, opening(cash));
      final workspace = engine.workspace;
      final currency = cash.currency;
      final broker = BrokerIdentity(
        id: PublicId.generate(),
        workspace: workspace,
        name: 'Synthetic broker',
      );
      final portfolio = InvestmentAccount(
        id: PublicId.generate(),
        workspace: workspace,
        brokerId: broker.id,
        fundingCashAccountId: cash.id,
        name: 'Synthetic portfolio',
        expectedVersion: 1,
      );
      final instrument = InvestmentInstrument(
        id: PublicId.generate(),
        kind: InstrumentKind.etf,
        marketCode: 'XNAS',
        symbol: 'TEST',
        name: 'Synthetic ETF',
        tradingCurrency: currency,
      );
      final funding = FundingCashAccount(
        id: cash.id,
        workspace: workspace,
        currency: currency,
        expectedVersion: 1,
      );
      final buy = InvestmentBuyPreview.create(
        id: PublicId.generate(),
        lotId: PublicId.generate(),
        operation: OperationKey(workspace, OperationId(PublicId.generate())),
        tradedOn: BusinessDate(2028, 2, 20),
        broker: broker,
        account: portfolio,
        instrument: instrument,
        funding: funding,
        quantity: ShareQuantity.parse('2'),
        unitPrice: ShareUnitPrice.parse(currency, '10'),
        executedGross: Money.parse(currency, '20'),
        fee: Money.parse(currency, '1'),
        tax: Money.parse(currency, '0'),
      );
      await engine.submitInvestmentBuy(buy);
      final sale = InvestmentSellPreview.create(
        id: PublicId.generate(),
        operation: OperationKey(workspace, OperationId(PublicId.generate())),
        tradedOn: BusinessDate(2028, 2, 21),
        broker: broker,
        account: portfolio,
        instrument: instrument,
        funding: funding,
        costMethod: InvestmentCostMethod.fifo,
        quantity: ShareQuantity.parse('1'),
        unitPrice: ShareUnitPrice.parse(currency, '30'),
        executedGross: Money.parse(currency, '30'),
        fee: Money.parse(currency, '1'),
        tax: Money.parse(currency, '0'),
        lots: await engine.investmentHoldingLots(portfolio.id, instrument.id),
      );
      await engine.submitInvestmentSell(sale);
      expect((await engine.accounts()).single.balance.majorText, '108.00');
      await engine.lock();

      engine = engineAt(work, vault, schemaVersion: 24);
      await expectLater(
        engine.unlock(password),
        throwsA(isA<PreviewUpgradeRequired>()),
      );
      await engine.upgrade(password);
      expect(engine.capabilities.investmentDividends, isTrue);
      expect(engine.capabilities.investmentSplits, isTrue);
      expect((await engine.investmentBuys()).single.preview.id, buy.id);
      expect(
        (await engine.investmentSales(
          portfolio.id,
          instrument.id,
        )).single.preview.id,
        sale.id,
      );
      final held = (await engine.investmentHoldingLots(
        portfolio.id,
        instrument.id,
      )).single;
      expect(held.remainingQuantity.toString(), '1');
      expect(held.remainingCost.majorText, '10.50');
      expect((await engine.accounts()).single.balance.majorText, '108.00');
      final copies = Directory('${work.path}/upgrade-backups')
          .listSync()
          .whereType<File>()
          .toList();
      expect(copies, hasLength(2));
      final schemas = <int>{};
      for (final copy in copies) {
        final encrypted = copy.readAsStringSync();
        final byPassword = await EnvelopeCodec().openWithPassword(
          encrypted,
          password,
        );
        final byRecovery = await EnvelopeCodec().openWithRecovery(
          encrypted,
          recoveryKey,
        );
        expect(byRecovery, byPassword);
        schemas.add(
          (jsonDecode(utf8.decode(byPassword)) as Map)['schema'] as int,
        );
      }
      expect(schemas, {22, 23});

      final split = StockSplitPreview.create(
        id: PublicId.generate(),
        operation: OperationKey(workspace, OperationId(PublicId.generate())),
        effectiveOn: BusinessDate(2028, 3, 15),
        broker: broker,
        account: portfolio,
        instrument: instrument,
        newShares: 2,
        oldShares: 1,
        lots: [held],
      );
      await engine.submitInvestmentSplit(split);
      expect(
        (await engine.investmentHoldingLots(
          portfolio.id,
          instrument.id,
        )).single.remainingQuantity.toString(),
        '2',
      );
      expect((await engine.accounts()).single.balance.majorText, '108.00');
      final backup = await engine.exportBackup();
      for (final useRecovery in [false, true]) {
        final restoredWork = root.createTempSync('restored-');
        final restored = engineAt(
          restoredWork,
          MemoryVault(),
          schemaVersion: 24,
        );
        try {
          await setup(restored);
          await restored.importBackup(
            backup,
            useRecovery ? recoveryKey : password,
            recovery: useRecovery,
          );
          expect((await restored.investmentBuys()).single.preview.id, buy.id);
          expect(
            (await restored.investmentSales(
              portfolio.id,
              instrument.id,
            )).single.preview.id,
            sale.id,
          );
          expect(
            (await restored.investmentSplits()).single.preview.id,
            split.id,
          );
          final lot = (await restored.investmentHoldingLots(
            portfolio.id,
            instrument.id,
          )).single;
          expect(lot.remainingQuantity.toString(), '2');
          expect(lot.remainingCost.majorText, '10.50');
          expect(
            (await restored.accounts()).single.balance.majorText,
            '108.00',
          );
        } finally {
          await restored.lock();
          deleteSynthetic(restoredWork, root);
        }
      }
    } finally {
      await engine.lock();
      deleteSynthetic(work, root);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
