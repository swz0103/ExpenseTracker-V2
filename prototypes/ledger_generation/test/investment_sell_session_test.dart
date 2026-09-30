import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:ledger_generation_probe/safety_backup.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/investment-sell-session-tests')
    ..createSync(recursive: true);
  final usd = Currency('USD', 2);
  const password = 'synthetic-sale-ledger-password';
  late Directory work, backups;
  late FixtureKeySlots keys;
  late LedgerStore source, target;
  late WorkspaceId workspace;
  late Account bank;
  late InvestmentBuyPreview buy;

  OperationId operationId() => OperationId(PublicId.generate());
  OperationKey operation() => OperationKey(workspace, operationId());
  PostingAccount bankRef() => PostingAccount(
    id: bank.id,
    workspace: workspace,
    currency: usd,
    expectedVersion: bank.version,
  );
  LedgerStore ledger(
    String name,
    FixtureKeySlots slots, {
    required bool sales,
  }) => LedgerStore(
    Directory('${work.path}/$name'),
    slots,
    catalogProtection: fixtureCatalogProtection(slots),
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
    creditCardsAware: true,
    cardStatementsAware: true,
    cardAuthorizationsAware: true,
    installmentsAware: true,
    investmentsAware: true,
    investmentSalesAware: sales,
  );

  setUp(() async {
    work = root.createTempSync('case-');
    backups = Directory('${work.path}/backups')..createSync();
    keys = FixtureKeySlots(Directory('${work.path}/keys'));
    workspace = WorkspaceId(PublicId.generate());
    source = ledger('store', keys, sales: false);
    await source.initialize(operationId());
    bank = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic bank',
      kind: AccountKind.bank,
      currency: usd,
      openedOn: BusinessDate(2028, 1, 1),
    );
    await source.withSession(
      (session) => session.createAccount(
        bank,
        Posting.opening(
          id: PublicId.generate(),
          operation: operation(),
          date: bank.openedOn,
          account: bankRef(),
          amount: Money.parse(usd, '100'),
        ),
      ),
    );
    final broker = BrokerIdentity(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic broker',
    );
    final account = InvestmentAccount(
      id: PublicId.generate(),
      workspace: workspace,
      brokerId: broker.id,
      fundingCashAccountId: bank.id,
      name: 'Synthetic portfolio',
      expectedVersion: 1,
    );
    final instrument = InvestmentInstrument(
      id: PublicId.generate(),
      kind: InstrumentKind.etf,
      marketCode: 'XNYS',
      symbol: 'SYN',
      name: 'Synthetic ETF',
      tradingCurrency: usd,
    );
    buy = InvestmentBuyPreview.create(
      id: PublicId.generate(),
      lotId: PublicId.generate(),
      operation: operation(),
      tradedOn: BusinessDate(2028, 2, 20),
      broker: broker,
      account: account,
      instrument: instrument,
      funding: FundingCashAccount(
        id: bank.id,
        workspace: workspace,
        currency: usd,
        expectedVersion: bank.version,
      ),
      quantity: ShareQuantity.parse('2'),
      unitPrice: ShareUnitPrice.parse(usd, '10'),
      executedGross: Money.parse(usd, '20'),
      fee: Money.parse(usd, '1'),
      tax: Money.parse(usd, '0'),
    );
    await source.withSession(
      (session) => session.postInvestmentBuy(buy, PublicId.generate()),
    );
    target = ledger('store', keys, sales: true);
  });

  tearDown(() {
    final base = root.resolveSymbolicLinksSync();
    final resolved = work.resolveSymbolicLinksSync();
    if (!resolved.startsWith('$base${Platform.pathSeparator}')) {
      throw StateError('Unsafe synthetic cleanup');
    }
    work.deleteSync(recursive: true);
  });

  Future<UpgradeRequest> request(String recoveryKey) async {
    final planned = await planInvestmentSaleUpgrade(
      target,
      operationId(),
      PublicId.generate(),
    );
    await upgradeInvestmentSales(
      target,
      planned,
      backups,
      password: password,
      recoveryKey: recoveryKey,
    );
    return planned;
  }

  test('21 to 22 keeps buy and starts with no sale facts', () async {
    final before = jsonDecode(utf8.decode(await source.snapshot())) as Map;
    final recovery = (await source.backup(password)).recoveryKey;
    await request(recovery);
    final after = jsonDecode(utf8.decode(await target.snapshot())) as Map;
    expect(after['schema'], 22);
    for (final entry in (before['tables'] as Map).entries) {
      expect((after['tables'] as Map)[entry.key], entry.value);
    }
    expect((after['tables'] as Map)['investment_sales'], isEmpty);
    expect((after['tables'] as Map)['investment_sale_allocations'], isEmpty);
  });

  test(
    'interrupted 21 to 22 upgrade keeps source and reuses safety copy',
    () async {
      final before = await source.snapshot();
      final recovery = (await source.backup(password)).recoveryKey;
      final planned = await planInvestmentSaleUpgrade(
        target,
        operationId(),
        PublicId.generate(),
      );
      Future<UpgradeReceipt> upgrade({void Function(String)? checkpoint}) =>
          upgradeInvestmentSales(
            target,
            planned,
            backups,
            password: password,
            recoveryKey: recovery,
            checkpoint: checkpoint,
          );
      await expectLater(
        upgrade(
          checkpoint: (point) {
            if (point.contains('table:investment_sales')) {
              throw StateError('synthetic staged interruption');
            }
          },
        ),
        throwsA(isA<GenerationUnavailable>()),
      );
      expect(await source.snapshot(), before);
      final safety = File('${backups.path}/${planned.backupId.value}.envelope');
      expect(safety.existsSync(), isTrue);
      final safetyBytes = safety.readAsBytesSync();
      await upgrade();
      expect(safety.readAsBytesSync(), safetyBytes);
      expect(
        (jsonDecode(utf8.decode(await target.snapshot())) as Map)['schema'],
        22,
      );
    },
  );

  test(
    'sale rolls back, retries once, then both credentials restore',
    () async {
      final recovery = (await source.backup(password)).recoveryKey;
      await request(recovery);
      final sale = await target.withSession((session) async {
        final lots = await session.investmentHoldingLots(
          workspace,
          buy.account.id,
          buy.instrument.id,
        );
        return InvestmentSellPreview.create(
          id: PublicId.generate(),
          operation: operation(),
          tradedOn: BusinessDate(2028, 2, 21),
          broker: buy.broker,
          account: buy.account,
          instrument: buy.instrument,
          funding: buy.funding,
          costMethod: InvestmentCostMethod.fifo,
          quantity: ShareQuantity.parse('1'),
          unitPrice: ShareUnitPrice.parse(usd, '30'),
          executedGross: Money.parse(usd, '30'),
          fee: Money.parse(usd, '1'),
          tax: Money.parse(usd, '0'),
          lots: lots,
        );
      });
      final eventId = PublicId.generate();
      final beforeSale = await target.snapshot();
      await target.withSession((session) async {
        await expectLater(
          session.postInvestmentSell(
            sale,
            eventId,
            checkpoint: (point) {
              if (point == 'investmentSellAllocation') {
                throw StateError('synthetic interruption');
              }
            },
          ),
          throwsStateError,
        );
        expect(await session.snapshot(), beforeSale);
        final first = await session.postInvestmentSell(sale, eventId);
        expect(first.replayed, isFalse);
        expect(
          (await session.postInvestmentSell(sale, eventId)).replayed,
          isTrue,
        );
        expect(
          (await session.investmentHoldingLots(
            workspace,
            buy.account.id,
            buy.instrument.id,
          )).single.remainingQuantity,
          ShareQuantity.parse('1'),
        );
        expect(
          (await session.accounts(workspace)).single.balance,
          Money.parse(usd, '108'),
        );
      });
      final current = await target.snapshot();
      final backup = await target.backup(password);
      for (final useRecovery in [false, true]) {
        final restoredKeys = FixtureKeySlots(
          Directory('${work.path}/keys-$useRecovery'),
        );
        final restored = ledger(
          'restored-$useRecovery',
          restoredKeys,
          sales: true,
        );
        await restored.restore(
          backup.envelope,
          operationId(),
          password: useRecovery ? null : password,
          recoveryKey: useRecovery ? backup.recoveryKey : null,
        );
        expect(await restored.snapshot(), current);
        await restored.withSession((session) async {
          expect(
            (await session.postInvestmentSell(sale, eventId)).replayed,
            isTrue,
          );
        });
      }
    },
  );
}
