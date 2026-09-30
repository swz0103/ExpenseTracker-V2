import 'dart:io';

import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:storage_generation_probe/generation_store.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/investment-dividend-flow-tests')
    ..createSync(recursive: true);

  test(
    'schema22 requires explicit safe upgrade before schema23 dividend',
    () async {
      final work = root.createTempSync('upgrade-');
      final vault = MemoryVault();
      var engine = engineAt(work, vault, schemaVersion: 22);
      try {
        await setup(engine);
        final cash = account(engine, name: 'Synthetic dividend cash');
        await engine.createAccount(cash, opening(cash));
        await engine.lock();
        var interrupted = false;
        engine = engineAt(
          work,
          vault,
          schemaVersion: 23,
          checkpoint: (point) {
            if (!interrupted && point == '22:table:investment_dividends') {
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
        engine = engineAt(work, vault, schemaVersion: 22);
        await engine.unlock(password);
        expect((await engine.accounts()).single.balance.majorText, '100.00');
        await engine.lock();
        engine = engineAt(work, vault, schemaVersion: 23);
        await engine.upgrade(password);
        expect((await engine.accounts()).single.balance.majorText, '100.00');
        expect(engine.capabilities.investmentDividends, isTrue);
        expect(await engine.investmentDividends(), isEmpty);
      } finally {
        await engine.lock();
        deleteSynthetic(work, root);
      }
    },
  );

  test(
    'acknowledgement loss retries one dividend after restart and restores',
    () async {
      final work = root.createTempSync('source-');
      final vault = MemoryVault();
      var interruptOnce = true;
      PreviewEngine open() => engineAt(
        work,
        vault,
        schemaVersion: 23,
        draftCheckpoint: (point) {
          if (point == 'investment-dividend-committed' && interruptOnce) {
            interruptOnce = false;
            throw StateError('synthetic acknowledgement loss');
          }
        },
      );
      var engine = open();
      try {
        final recoveryKey = await setup(engine);
        final cash = account(engine, name: 'Synthetic dividend cash');
        await engine.createAccount(cash, opening(cash));
        final funding = (await engine.accounts()).single;
        final workspace = engine.workspace;
        final twd = Currency('TWD', 2);
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
          tradingCurrency: twd,
        );
        final fundingAccount = FundingCashAccount(
          id: cash.id,
          workspace: workspace,
          currency: twd,
          expectedVersion: funding.account.version,
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
            funding: fundingAccount,
            quantity: ShareQuantity.parse('2'),
            unitPrice: ShareUnitPrice.parse(twd, '10'),
            executedGross: Money.parse(twd, '20'),
            fee: Money.parse(twd, '1'),
            tax: Money.parse(twd, '0'),
          ),
        );
        final dividend = InvestmentDividendPreview.create(
          id: PublicId.generate(),
          operation: OperationKey(workspace, OperationId(PublicId.generate())),
          paidOn: BusinessDate(2028, 3, 15),
          broker: broker,
          account: investmentAccount,
          instrument: instrument,
          funding: fundingAccount,
          gross: Money.parse(twd, '10'),
          withholdingTax: Money.parse(twd, '1'),
          fee: Money.parse(twd, '0.25'),
          reportedNet: Money.parse(twd, '8.75'),
        );
        await expectLater(
          engine.submitInvestmentDividend(dividend),
          throwsA(isA<StateError>()),
        );
        expect(await engine.hasPendingInvestmentDividend(), isTrue);
        expect(await engine.investmentDividends(), hasLength(1));
        await engine.lock();
        engine = open();
        await engine.unlock(password);
        await engine.retryPendingInvestmentDividend();
        expect(await engine.hasPendingInvestmentDividend(), isFalse);
        expect(await engine.investmentDividends(), hasLength(1));
        expect((await engine.accounts()).single.balance.majorText, '87.75');
        final backup = await engine.exportBackup();
        for (final useRecovery in [false, true]) {
          final targetDir = root.createTempSync('restore-');
          final target = engineAt(targetDir, MemoryVault(), schemaVersion: 23);
          try {
            await setup(target);
            await target.importBackup(
              backup,
              useRecovery ? recoveryKey : password,
              recovery: useRecovery,
            );
            expect(await target.investmentDividends(), hasLength(1));
            expect((await target.accounts()).single.balance.majorText, '87.75');
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
