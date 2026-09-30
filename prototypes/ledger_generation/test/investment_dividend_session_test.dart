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
  final root = Directory('.dart_tool/investment-dividend-session-tests')
    ..createSync(recursive: true);
  final usd = Currency('USD', 2);
  const password = 'synthetic-dividend-ledger-password';
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
    required bool dividends,
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
    investmentSalesAware: true,
    investmentDividendsAware: dividends,
  );

  setUp(() async {
    work = root.createTempSync('case-');
    backups = Directory('${work.path}/backups')..createSync();
    keys = FixtureKeySlots(Directory('${work.path}/keys'));
    workspace = WorkspaceId(PublicId.generate());
    source = ledger('store', keys, dividends: false);
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
    target = ledger('store', keys, dividends: true);
  });

  tearDown(() {
    final base = root.resolveSymbolicLinksSync();
    final resolved = work.resolveSymbolicLinksSync();
    if (!resolved.startsWith('$base${Platform.pathSeparator}')) {
      throw StateError('Unsafe synthetic cleanup');
    }
    work.deleteSync(recursive: true);
  });

  Future<void> upgrade(String recoveryKey) async {
    final planned = await planInvestmentDividendUpgrade(
      target,
      operationId(),
      PublicId.generate(),
    );
    await upgradeInvestmentDividends(
      target,
      planned,
      backups,
      password: password,
      recoveryKey: recoveryKey,
    );
  }

  InvestmentDividendPreview dividend() => InvestmentDividendPreview.create(
    id: PublicId.generate(),
    operation: operation(),
    paidOn: BusinessDate(2028, 3, 15),
    broker: buy.broker,
    account: buy.account,
    instrument: buy.instrument,
    funding: buy.funding,
    gross: Money.parse(usd, '10'),
    withholdingTax: Money.parse(usd, '1'),
    fee: Money.parse(usd, '0.25'),
    reportedNet: Money.parse(usd, '8.75'),
  );

  test(
    '22 to 23 preserves all earlier rows and adds empty dividend table',
    () async {
      final before = jsonDecode(utf8.decode(await source.snapshot())) as Map;
      final recovery = (await source.backup(password)).recoveryKey;
      await upgrade(recovery);
      final after = jsonDecode(utf8.decode(await target.snapshot())) as Map;
      expect(after['schema'], 23);
      for (final entry in (before['tables'] as Map).entries) {
        expect((after['tables'] as Map)[entry.key], entry.value);
      }
      expect((after['tables'] as Map)['investment_dividends'], isEmpty);
    },
  );

  test('interrupted upgrade retains schema22 source and safety copy', () async {
    final before = await source.snapshot();
    final recovery = (await source.backup(password)).recoveryKey;
    final planned = await planInvestmentDividendUpgrade(
      target,
      operationId(),
      PublicId.generate(),
    );
    Future<UpgradeReceipt> attempt({void Function(String)? checkpoint}) =>
        upgradeInvestmentDividends(
          target,
          planned,
          backups,
          password: password,
          recoveryKey: recovery,
          checkpoint: checkpoint,
        );
    await expectLater(
      attempt(
        checkpoint: (point) {
          if (point.contains('table:investment_dividends')) {
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
    await attempt();
    expect(safety.readAsBytesSync(), safetyBytes);
    expect(
      (jsonDecode(utf8.decode(await target.snapshot())) as Map)['schema'],
      23,
    );
  });

  test(
    'dividend rollback, same-ID retry and both credential restores',
    () async {
      final recovery = (await source.backup(password)).recoveryKey;
      await upgrade(recovery);
      final preview = dividend();
      final eventId = PublicId.generate();
      final before = await target.snapshot();
      await target.withSession((session) async {
        await expectLater(
          session.postInvestmentDividend(
            preview,
            eventId,
            checkpoint: (point) {
              if (point == 'investmentDividend') {
                throw StateError('synthetic interruption');
              }
            },
          ),
          throwsStateError,
        );
        expect(await session.snapshot(), before);
        expect(
          (await session.postInvestmentDividend(preview, eventId)).replayed,
          isFalse,
        );
        expect(
          (await session.postInvestmentDividend(preview, eventId)).replayed,
          isTrue,
        );
        expect(
          (await session.investmentDividends(workspace)).single.eventId,
          eventId,
        );
        expect(
          (await session.accounts(workspace)).single.balance,
          Money.parse(usd, '87.75'),
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
          dividends: true,
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
            (await session.postInvestmentDividend(preview, eventId)).replayed,
            isTrue,
          );
        });
      }
    },
  );
}
