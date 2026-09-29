import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:investments/investments.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart';
import 'package:modular_persistence_probe/investment_adapter.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:test/test.dart';
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/investment-sale-snapshot-tests')
    ..createSync(recursive: true);
  final codec = SnapshotCodec(
    generationAware: true,
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
    recurringAware: true,
    creditCardsAware: true,
    cardStatementsAware: true,
    cardAuthorizationsAware: true,
    installmentsAware: true,
    investmentsAware: true,
    investmentSalesAware: true,
  );
  ProbeDatabase database(
    File file,
    StorageBinding binding, {
    bool sales = true,
  }) => ProbeDatabase(
    file,
    storageBinding: binding,
    categoryAware: true,
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

  late Directory work;
  late ProbeDatabase source;
  late AllocationFixture fixture;
  late InvestmentBuyPreview buy;
  late InvestmentSellPreview sell;
  late Posting sellPosting;

  setUp(() async {
    work = root.createTempSync('case-');
    source = database(File('${work.path}/source.db'), allocationBinding());
    fixture = AllocationFixture(source);
    await fixture.initialize();
    final broker = BrokerIdentity(
      id: PublicId.generate(),
      workspace: fixture.ws,
      name: 'Synthetic broker',
    );
    final account = InvestmentAccount(
      id: PublicId.generate(),
      workspace: fixture.ws,
      brokerId: broker.id,
      fundingCashAccountId: fixture.account.id,
      name: 'Synthetic portfolio',
      expectedVersion: 1,
    );
    final instrument = InvestmentInstrument(
      id: PublicId.generate(),
      kind: InstrumentKind.etf,
      marketCode: 'XNYS',
      symbol: 'SYN',
      name: 'Synthetic ETF',
      tradingCurrency: fixture.currency,
    );
    final funding = FundingCashAccount(
      id: fixture.account.id,
      workspace: fixture.ws,
      currency: fixture.currency,
      expectedVersion: 1,
    );
    buy = InvestmentBuyPreview.create(
      id: PublicId.generate(),
      lotId: PublicId.generate(),
      operation: fixture.operation(),
      tradedOn: BusinessDate(2028, 2, 20),
      broker: broker,
      account: account,
      instrument: instrument,
      funding: funding,
      quantity: ShareQuantity.parse('2'),
      unitPrice: ShareUnitPrice.parse(fixture.currency, '10'),
      executedGross: fixture.money('20'),
      fee: fixture.money('1'),
      tax: fixture.money('0'),
    );
    await commitInvestmentBuy(
      source,
      buy,
      Posting.investmentBuy(
        id: PublicId.generate(),
        operation: buy.operation,
        date: buy.tradedOn,
        account: fixture.reference,
        investmentBuyId: buy.id,
        gross: buy.gross,
        fee: buy.fee,
        tax: buy.tax,
        cashDebit: buy.cashDebit,
      ),
    );
    sell = InvestmentSellPreview.create(
      id: PublicId.generate(),
      operation: fixture.operation(),
      tradedOn: BusinessDate(2028, 2, 21),
      broker: broker,
      account: account,
      instrument: instrument,
      funding: funding,
      costMethod: InvestmentCostMethod.fifo,
      quantity: ShareQuantity.parse('1'),
      unitPrice: ShareUnitPrice.parse(fixture.currency, '30'),
      executedGross: fixture.money('30'),
      fee: fixture.money('1'),
      tax: fixture.money('0'),
      lots: await investmentHoldingLots(
        source,
        fixture.ws,
        account.id,
        instrument.id,
      ),
    );
    sellPosting = Posting.investmentSell(
      id: PublicId.generate(),
      operation: sell.operation,
      date: sell.tradedOn,
      account: fixture.reference,
      investmentSellId: sell.id,
      gross: sell.gross,
      fee: sell.fee,
      tax: sell.tax,
      cashCredit: sell.cashCredit,
    );
    await commitInvestmentSell(source, sell, sellPosting);
  });

  tearDown(() async {
    await source.close();
    await work.delete(recursive: true);
  });

  test('schema 22 sale and lots survive portable stage without loss', () async {
    final bytes = await codec.capture(source);
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(json['version'], 21);
    expect(json['schema'], 22);
    expect((json['tables'] as Map)['investment_sales'], hasLength(1));
    expect(
      (json['tables'] as Map)['investment_sale_allocations'],
      hasLength(1),
    );
    final binding = allocationBinding();
    final file = File('${work.path}/restored.db');
    await codec.stage(bytes, file, openDatabase: (f) => database(f, binding));
    final target = database(file, binding);
    try {
      expect(await codec.capture(target), bytes);
      expect(
        (await investmentHoldingLots(
          target,
          fixture.ws,
          buy.account.id,
          buy.instrument.id,
        )).single.remainingQuantity,
        ShareQuantity.parse('1'),
      );
      await validateInvestmentSaleFacts(target);
    } finally {
      await target.close();
    }
  });

  test('changed allocation is rejected during staged restore', () async {
    final tampered = jsonDecode(
      utf8.decode(await codec.capture(source)),
    ) as Map<String, dynamic>;
    ((tampered['tables'] as Map)['investment_sale_allocations'] as List)
            .single['remaining_cost'] =
        '999';
    await expectLater(
      codec.stage(
        utf8.encode(jsonEncode(tampered)),
        File('${work.path}/tampered.db'),
        openDatabase: (f) => database(f, allocationBinding()),
      ),
      throwsA(isA<InvalidSnapshot>()),
    );
  });

  test('schema 21 upgrades with empty sale authority', () async {
    final oldCodec = SnapshotCodec(
      generationAware: true,
      correctionsAware: true,
      tombstonesAware: true,
      budgetsAware: true,
      recurringAware: true,
      creditCardsAware: true,
      cardStatementsAware: true,
      cardAuthorizationsAware: true,
      installmentsAware: true,
      investmentsAware: true,
    );
    final old = database(
      File('${work.path}/old.db'),
      allocationBinding(),
      sales: false,
    );
    final List<int> legacy;
    try {
      await AllocationFixture(old).initialize();
      legacy = await oldCodec.capture(old);
    } finally {
      await old.close();
    }
    final upgraded = jsonDecode(
      utf8.decode(codec.canonicalize(legacy)),
    ) as Map<String, dynamic>;
    expect(upgraded['version'], 21);
    expect(upgraded['schema'], 22);
    expect((upgraded['tables'] as Map)['investment_sales'], isEmpty);
    expect((upgraded['tables'] as Map)['investment_sale_allocations'], isEmpty);
    final binding = allocationBinding();
    final file = File('${work.path}/upgraded.db');
    await codec.stage(legacy, file, openDatabase: (f) => database(f, binding));
    final target = database(file, binding);
    try {
      expect(await codec.capture(target), codec.canonicalize(legacy));
    } finally {
      await target.close();
    }
  });

  test(
    'password and recovery text independently restore sale authority',
    () async {
      const password = 'synthetic-sale-backup-password';
      final bytes = await codec.capture(source);
      final envelope = await EnvelopeCodec().create(bytes, password: password);
      final opened = <List<int>>[
        await EnvelopeCodec().openWithPassword(envelope.envelope, password),
        await EnvelopeCodec().openWithRecovery(
          envelope.envelope,
          envelope.recoveryKey,
        ),
      ];
      for (var index = 0; index < opened.length; index++) {
        expect(opened[index], bytes);
        final binding = allocationBinding();
        final file = File('${work.path}/credential-$index.db');
        await codec.stage(
          opened[index],
          file,
          openDatabase: (f) => database(f, binding),
        );
        final target = database(file, binding);
        try {
          expect(await codec.capture(target), bytes);
        } finally {
          await target.close();
        }
      }
      await expectLater(
        EnvelopeCodec().openWithPassword(envelope.envelope, 'wrong-password'),
        throwsA(isA<BackupException>()),
      );
    },
  );
}
