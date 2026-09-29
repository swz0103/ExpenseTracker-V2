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
  final root = Directory('.dart_tool/investment-buy-session-tests')
    ..createSync(recursive: true);
  final usd = Currency('USD', 2);
  const password = 'synthetic-investment-backup-password';
  late Directory work, backups;
  late FixtureKeySlots keys;
  late LedgerStore source, target;
  late WorkspaceId workspace;
  late Account bank;

  OperationId operationId() => OperationId(PublicId.generate());
  OperationKey operation() => OperationKey(workspace, operationId());
  PostingAccount bankRef() => PostingAccount(
    id: bank.id,
    workspace: workspace,
    currency: usd,
    expectedVersion: bank.version,
  );
  LedgerStore ledger(
    String path,
    FixtureKeySlots slots, {
    required bool buys,
  }) => LedgerStore(
    Directory('${work.path}/$path'),
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
    investmentsAware: buys,
  );

  InvestmentBuyPreview preview({
    required OperationKey operation,
    required PublicId buyId,
    required PublicId lotId,
    Money? fee,
  }) {
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
      symbol: 'TEST',
      name: 'Synthetic ETF',
      tradingCurrency: usd,
    );
    return InvestmentBuyPreview.create(
      id: buyId,
      lotId: lotId,
      operation: operation,
      tradedOn: BusinessDate(2026, 9, 30),
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
      unitPrice: ShareUnitPrice.parse(usd, '10.25'),
      executedGross: Money.parse(usd, '20.50'),
      fee: fee ?? Money.parse(usd, '0.50'),
      tax: Money.parse(usd, '0'),
    );
  }

  setUp(() async {
    work = root.createTempSync('case-');
    backups = Directory('${work.path}/backups')..createSync();
    keys = FixtureKeySlots(Directory('${work.path}/keys'));
    workspace = WorkspaceId(PublicId.generate());
    source = ledger('store', keys, buys: false);
    await source.initialize(operationId());
    bank = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'Synthetic bank',
      kind: AccountKind.bank,
      currency: usd,
      openedOn: BusinessDate(2026, 1, 1),
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
    target = ledger('store', keys, buys: true);
  });

  tearDown(() {
    final base = root.resolveSymbolicLinksSync();
    final resolved = work.resolveSymbolicLinksSync();
    if (!resolved.startsWith('$base${Platform.pathSeparator}')) {
      throw StateError('Unsafe synthetic cleanup');
    }
    work.deleteSync(recursive: true);
  });

  Future<void> upgrade() async {
    final recoveryKey = (await source.backup(password)).recoveryKey;
    final request = await planInvestmentUpgrade(
      target,
      operationId(),
      PublicId.generate(),
    );
    await upgradeInvestments(
      target,
      request,
      backups,
      password: password,
      recoveryKey: recoveryKey,
    );
  }

  test('schema 20 rejects buys; 20 to 21 preserves bank authority', () async {
    final before = jsonDecode(utf8.decode(await source.snapshot())) as Map;
    final buy = preview(
      operation: operation(),
      buyId: PublicId.generate(),
      lotId: PublicId.generate(),
    );
    await source.withSession((session) async {
      await expectLater(
        session.postInvestmentBuy(buy, PublicId.generate()),
        throwsUnsupportedError,
      );
    });
    await upgrade();
    final after = jsonDecode(utf8.decode(await target.snapshot())) as Map;
    expect(after['schema'], 21);
    for (final entry in (before['tables'] as Map).entries) {
      expect((after['tables'] as Map)[entry.key], entry.value);
    }
    expect((after['tables'] as Map)['investment_buys'], isEmpty);
    expect((after['tables'] as Map)['investment_lots'], isEmpty);
  });

  test(
    'interrupted schema 21 stage retains schema 20 and safely retries',
    () async {
      final before = await source.snapshot();
      final recoveryKey = (await source.backup(password)).recoveryKey;
      final request = await planInvestmentUpgrade(
        target,
        operationId(),
        PublicId.generate(),
      );
      await expectLater(
        upgradeInvestments(
          target,
          request,
          backups,
          password: password,
          recoveryKey: recoveryKey,
          checkpoint: (point) {
            if (point == 'table:investment_lots') {
              throw StateError('synthetic upgrade interruption');
            }
          },
        ),
      throwsA(isA<GenerationUnavailable>()),
    );
    expect(await source.snapshot(), before);
    target = ledger('store', keys, buys: true);
      await upgradeInvestments(
        target,
        request,
        backups,
        password: password,
        recoveryKey: recoveryKey,
      );
      final after = jsonDecode(utf8.decode(await target.snapshot())) as Map;
      expect(after['schema'], 21);
      for (final entry
          in ((jsonDecode(utf8.decode(before)) as Map)['tables'] as Map)
              .entries) {
        expect((after['tables'] as Map)[entry.key], entry.value);
      }
    },
  );

  test(
    'buy debits cash once; interruption rolls back and both keys restore',
    () async {
      await upgrade();
      final buy = preview(
        operation: operation(),
        buyId: PublicId.generate(),
        lotId: PublicId.generate(),
      );
      final eventId = PublicId.generate();
      final before = await target.snapshot();
      await target.withSession((session) async {
        await expectLater(
          session.postInvestmentBuy(
            buy,
            eventId,
            checkpoint: (point) {
              if (point == 'investmentLot') {
                throw StateError('synthetic write interruption');
              }
            },
          ),
          throwsStateError,
        );
        expect(await session.snapshot(), before);
        final result = await session.postInvestmentBuy(buy, eventId);
        expect(result.replayed, isFalse);
        expect(result.id, eventId);
        expect(
          (await session.accounts(workspace)).single.balance,
          Money.parse(usd, '79'),
        );
        final saved = await session.snapshot();
        final replay = await session.postInvestmentBuy(buy, eventId);
        expect(replay.replayed, isTrue);
        expect(await session.snapshot(), saved);
      });
      final current = await target.snapshot();
      final tables = (jsonDecode(utf8.decode(current)) as Map)['tables'] as Map;
      expect(tables['investment_buys'], hasLength(1));
      expect(tables['investment_lots'], hasLength(1));

      final backup = await target.backup(password);
      for (final useRecovery in [false, true]) {
        final restoredKeys = FixtureKeySlots(
          Directory('${work.path}/keys-$useRecovery'),
        );
        final restored = ledger(
          'restored-$useRecovery',
          restoredKeys,
          buys: true,
        );
        await restored.restore(
          backup.envelope,
          operationId(),
          password: useRecovery ? null : password,
          recoveryKey: useRecovery ? backup.recoveryKey : null,
        );
        expect(await restored.snapshot(), current);
      }
    },
  );
}
