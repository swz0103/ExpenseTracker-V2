import 'dart:io';

import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/investment-flow-tests')
    ..createSync(recursive: true);

  test('ambiguous buy survives restart and encrypted dual restore', () async {
    final work = root.createTempSync('source-');
    final vault = MemoryVault();
    var interruptOnce = true;
    PreviewEngine open() => engineAt(
      work,
      vault,
      schemaVersion: 21,
      draftCheckpoint: (point) {
        if (point == 'investment-buy-committed' && interruptOnce) {
          interruptOnce = false;
          throw StateError('synthetic acknowledgement loss');
        }
      },
    );
    var engine = open();
    try {
      final recoveryKey = await setup(engine);
      final cash = account(engine, name: 'Synthetic funding cash');
      await engine.createAccount(cash, opening(cash));
      final funding = (await engine.accounts()).single;
      final workspace = engine.workspace;
      final twd = Currency('TWD', 2);
      final broker = BrokerIdentity(
        id: PublicId.generate(),
        workspace: workspace,
        name: 'Synthetic broker',
      );
      final preview = InvestmentBuyPreview.create(
        id: PublicId.generate(),
        lotId: PublicId.generate(),
        operation: OperationKey(workspace, OperationId(PublicId.generate())),
        tradedOn: BusinessDate(2026, 9, 29),
        broker: broker,
        account: InvestmentAccount(
          id: PublicId.generate(),
          workspace: workspace,
          brokerId: broker.id,
          fundingCashAccountId: funding.account.id,
          name: 'Synthetic portfolio',
          expectedVersion: 1,
        ),
        instrument: InvestmentInstrument(
          id: PublicId.generate(),
          kind: InstrumentKind.etf,
          marketCode: 'XNAS',
          symbol: 'TEST',
          name: 'Synthetic ETF',
          tradingCurrency: twd,
        ),
        funding: FundingCashAccount(
          id: funding.account.id,
          workspace: workspace,
          currency: twd,
          expectedVersion: funding.account.version,
        ),
        quantity: ShareQuantity.parse('2'),
        unitPrice: ShareUnitPrice.parse(twd, '10.25'),
        executedGross: Money.parse(twd, '20.50'),
        fee: Money.parse(twd, '0.50'),
        tax: Money.parse(twd, '0'),
      );
      await expectLater(
        engine.submitInvestmentBuy(preview),
        throwsA(isA<StateError>()),
      );
      expect(await engine.hasPendingInvestmentBuy(), isTrue);
      expect(await engine.investmentBuys(), hasLength(1));
      await engine.lock();
      engine = open();
      await engine.unlock(password);
      expect(
        await engine.resolvePendingInvestmentBuy(),
        InvestmentIntentResolution.committed,
      );
      expect(await engine.hasPendingInvestmentBuy(), isFalse);
      expect(await engine.investmentBuys(), hasLength(1));
      expect((await engine.accounts()).single.balance.majorText, '79.00');
      expect(
        (await engine.entries()).where(
          (row) => row.kind == PostingKind.investmentBuy,
        ),
        hasLength(1),
      );
      final backup = await engine.exportBackup();
      for (final useRecovery in [false, true]) {
        final targetDir = root.createTempSync('restore-');
        final target = engineAt(targetDir, MemoryVault(), schemaVersion: 21);
        try {
          await setup(target);
          await target.importBackup(
            backup,
            useRecovery ? recoveryKey : password,
            recovery: useRecovery,
          );
          expect(await target.investmentBuys(), hasLength(1));
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
  });

  test(
    'certainly rejected buy can be discarded only after ledger check',
    () async {
      final work = root.createTempSync('rejected-');
      final vault = MemoryVault();
      final engine = engineAt(work, vault, schemaVersion: 21);
      try {
        await setup(engine);
        final cash = account(engine, name: 'Rejected funding cash');
        await engine.createAccount(cash, opening(cash));
        final funding = (await engine.accounts()).single;
        final workspace = engine.workspace;
        final twd = Currency('TWD', 2);
        final broker = BrokerIdentity(
          id: PublicId.generate(),
          workspace: workspace,
          name: 'Rejected broker',
        );
        final preview = InvestmentBuyPreview.create(
          id: PublicId.generate(),
          lotId: PublicId.generate(),
          operation: OperationKey(workspace, OperationId(PublicId.generate())),
          tradedOn: BusinessDate(2026, 9, 29),
          broker: broker,
          account: InvestmentAccount(
            id: PublicId.generate(),
            workspace: workspace,
            brokerId: broker.id,
            fundingCashAccountId: funding.account.id,
            name: 'Rejected portfolio',
            expectedVersion: 1,
          ),
          instrument: InvestmentInstrument(
            id: PublicId.generate(),
            kind: InstrumentKind.stock,
            marketCode: 'XNAS',
            symbol: 'REJECT',
            name: 'Rejected stock',
            tradingCurrency: twd,
          ),
          funding: FundingCashAccount(
            id: funding.account.id,
            workspace: workspace,
            currency: twd,
            expectedVersion: funding.account.version + 1,
          ),
          quantity: ShareQuantity.parse('1'),
          unitPrice: ShareUnitPrice.parse(twd, '10'),
          executedGross: Money.parse(twd, '10'),
          fee: Money.parse(twd, '0'),
          tax: Money.parse(twd, '0'),
        );

        await expectLater(
          engine.submitInvestmentBuy(preview),
          throwsA(isA<Exception>()),
        );
        expect(await engine.hasPendingInvestmentBuy(), isTrue);
        expect(await engine.investmentBuys(), isEmpty);
        vault.failWrites = true;
        await expectLater(
          engine.resolvePendingInvestmentBuy(),
          throwsA(isA<StateError>()),
        );
        expect(await engine.hasPendingInvestmentBuy(), isTrue);
        vault.failWrites = false;
        expect(
          await engine.resolvePendingInvestmentBuy(),
          InvestmentIntentResolution.discarded,
        );
        expect(await engine.hasPendingInvestmentBuy(), isFalse);
        expect(await engine.investmentBuys(), isEmpty);
        expect((await engine.accounts()).single.balance.majorText, '100.00');
      } finally {
        await engine.lock();
        deleteSynthetic(work, root);
      }
    },
  );
}
