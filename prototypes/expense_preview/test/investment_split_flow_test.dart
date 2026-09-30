import 'dart:io';

import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:storage_generation_probe/generation_store.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/investment-split-flow-tests')
    ..createSync(recursive: true);

  test('schema23 requires explicit safe upgrade before split', () async {
    final work = root.createTempSync('upgrade-');
    final vault = MemoryVault();
    var engine = engineAt(work, vault, schemaVersion: 23);
    try {
      await setup(engine);
      final cash = account(engine, name: 'Synthetic split cash');
      await engine.createAccount(cash, opening(cash));
      await engine.lock();
      var interrupted = false;
      engine = engineAt(
        work,
        vault,
        schemaVersion: 24,
        checkpoint: (point) {
          if (!interrupted && point == '23:table:investment_splits') {
            interrupted = true;
            throw StateError('synthetic staged interruption');
          }
        },
      );
      await expectLater(
        engine.unlock(password),
        throwsA(isA<PreviewUpgradeRequired>()),
      );
      await expectLater(
        engine.upgrade(password),
        throwsA(isA<GenerationUnavailable>()),
      );
      expect(interrupted, isTrue);
      await engine.lock();
      engine = engineAt(work, vault, schemaVersion: 23);
      await engine.unlock(password);
      expect((await engine.accounts()).single.balance.majorText, '100.00');
      await engine.lock();
      engine = engineAt(work, vault, schemaVersion: 24);
      await engine.upgrade(password);
      expect(engine.capabilities.investmentSplits, isTrue);
      expect(await engine.investmentSplits(), isEmpty);
    } finally {
      await engine.lock();
      deleteSynthetic(work, root);
    }
  });

  test(
    'acknowledgement loss retries exactly one split after restart and restores',
    () async {
      final work = root.createTempSync('source-');
      final vault = MemoryVault();
      var interruptOnce = true;
      PreviewEngine open() => engineAt(
        work,
        vault,
        schemaVersion: 24,
        draftCheckpoint: (point) {
          if (point == 'investment-split-committed' && interruptOnce) {
            interruptOnce = false;
            throw StateError('synthetic acknowledgement loss');
          }
        },
      );
      var engine = open();
      try {
        final recoveryKey = await setup(engine);
        final cash = account(engine, name: 'Synthetic split cash');
        await engine.createAccount(cash, opening(cash));
        final workspace = engine.workspace;
        final currency = cash.currency;
        final broker = BrokerIdentity(
          id: PublicId.generate(),
          workspace: workspace,
          name: 'Synthetic broker',
        );
        final investmentAccount = InvestmentAccount(
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
          expectedVersion: cash.version,
        );
        await engine.submitInvestmentBuy(
          InvestmentBuyPreview.create(
            id: PublicId.generate(),
            lotId: PublicId.generate(),
            operation: OperationKey(
              workspace,
              OperationId(PublicId.generate()),
            ),
            tradedOn: BusinessDate(2028, 2, 20),
            broker: broker,
            account: investmentAccount,
            instrument: instrument,
            funding: funding,
            quantity: ShareQuantity.parse('2'),
            unitPrice: ShareUnitPrice.parse(currency, '10'),
            executedGross: Money.parse(currency, '20'),
            fee: Money.parse(currency, '1'),
            tax: Money.parse(currency, '0'),
          ),
        );
        final lots = await engine.investmentHoldingLots(
          investmentAccount.id,
          instrument.id,
        );
        final split = StockSplitPreview.create(
          id: PublicId.generate(),
          operation: OperationKey(workspace, OperationId(PublicId.generate())),
          effectiveOn: BusinessDate(2028, 3, 15),
          broker: broker,
          account: investmentAccount,
          instrument: instrument,
          newShares: 2,
          oldShares: 1,
          lots: lots,
        );
        await expectLater(
          engine.submitInvestmentSplit(split),
          throwsStateError,
        );
        expect(await engine.hasPendingInvestmentSplit(), isTrue);
        expect((await engine.investmentSplits()).single.preview.id, split.id);
        await engine.lock();
        engine = open();
        await engine.unlock(password);
        await engine.retryPendingInvestmentSplit();
        expect(await engine.hasPendingInvestmentSplit(), isFalse);
        expect(await engine.investmentSplits(), hasLength(1));
        expect(
          (await engine.investmentHoldingLots(
            investmentAccount.id,
            instrument.id,
          )).single.remainingQuantity.toString(),
          '4',
        );
        expect((await engine.accounts()).single.balance.majorText, '79.00');
        final backup = await engine.exportBackup();
        for (final useRecovery in [false, true]) {
          final targetDir = root.createTempSync('restore-');
          final target = engineAt(targetDir, MemoryVault(), schemaVersion: 24);
          try {
            await setup(target);
            await target.importBackup(
              backup,
              useRecovery ? recoveryKey : password,
              recovery: useRecovery,
            );
            expect(
              (await target.investmentSplits()).single.preview.id,
              split.id,
            );
            expect(
              (await target.investmentHoldingLots(
                investmentAccount.id,
                instrument.id,
              )).single.remainingQuantity.toString(),
              '4',
            );
            expect((await target.accounts()).single.balance.majorText, '79.00');
          } finally {
            await target.lock();
            deleteSynthetic(targetDir, root);
          }
        }
      } finally {
        await engine.lock();
        deleteSynthetic(work, root);
      }
    },
  );
}
