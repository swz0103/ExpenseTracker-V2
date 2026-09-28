import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:reports/reports.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/monthly-report-tests')
    ..createSync(recursive: true);
  final twd = Currency('TWD', 2);
  final usd = Currency('USD', 2);
  late Directory work;
  late WorkspaceId workspace;
  late LedgerStore store;
  late Account cash, foreign;

  OperationId opId() => OperationId(PublicId.generate());
  OperationKey operation() => OperationKey(workspace, opId());
  Money money(Currency currency, String value) => Money.parse(currency, value);
  PostingAccount ref(Account account) => PostingAccount(
    id: account.id,
    workspace: workspace,
    currency: account.currency,
    expectedVersion: account.version,
  );
  LedgerStore open(String name) {
    final keys = FixtureKeySlots(Directory('${work.path}/$name-keys'));
    return LedgerStore(
      Directory('${work.path}/$name'),
      keys,
      catalogProtection: fixtureCatalogProtection(keys),
      correctionsAware: true,
      tombstonesAware: true,
    );
  }

  setUp(() async {
    work = root.createTempSync('case-');
    workspace = WorkspaceId(PublicId.generate());
    store = open('source');
    await store.initialize(opId());
    cash = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'cash',
      kind: AccountKind.cash,
      currency: twd,
      openedOn: BusinessDate(2026, 1, 1),
    );
    foreign = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'foreign',
      kind: AccountKind.bank,
      currency: usd,
      openedOn: BusinessDate(2026, 1, 1),
    );
    await store.withSession((session) async {
      for (final account in [cash, foreign]) {
        await session.createAccount(
          account,
          Posting.opening(
            id: PublicId.generate(),
            operation: operation(),
            date: account.openedOn,
            account: ref(account),
            amount: money(account.currency, '100'),
          ),
        );
      }
    });
  });
  tearDown(() {
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe synthetic cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test(
    'month and denomination reflect signed report facts, not cash legs',
    () async {
      final september = BusinessDate(2026, 9, 28);
      final october = BusinessDate(2026, 10, 2);
      final food = PublicId.generate(), travel = PublicId.generate();
      final earned = Posting.income(
        id: PublicId.generate(),
        operation: operation(),
        date: september,
        account: ref(cash),
        amount: money(twd, '100'),
      );
      final spent = Posting.expense(
        id: PublicId.generate(),
        operation: operation(),
        date: september,
        account: ref(cash),
        amount: money(twd, '40'),
        allocations: [
          Allocation(food, money(twd, '25'), expectedCategoryVersion: 1),
          Allocation(travel, money(twd, '15'), expectedCategoryVersion: 1),
        ],
      );
      final erased = Posting.expense(
        id: PublicId.generate(),
        operation: operation(),
        date: september,
        account: ref(cash),
        amount: money(twd, '5'),
      );
      final transfer = Posting.transfer(
        id: PublicId.generate(),
        operation: operation(),
        date: september,
        source: ref(cash),
        destination: ref(foreign),
        principal: money(twd, '20'),
        received: money(usd, '0.60'),
        fee: money(twd, '2'),
      );
      final refund = Posting.refund(
        id: PublicId.generate(),
        operation: operation(),
        date: october,
        account: ref(foreign),
        originalId: spent.id,
        amount: money(twd, '10'),
        received: money(usd, '0.30'),
        allocations: [
          Allocation(food, money(twd, '10'), expectedCategoryVersion: 1),
        ],
      );
      final reversal = Posting.reversal(
        id: PublicId.generate(),
        operation: operation(),
        date: october,
        original: earned,
      );
      await store.withSession((session) async {
        await session.createCategory(
          operation(),
          food,
          'food',
          CategoryKind.expense,
        );
        await session.createCategory(
          operation(),
          travel,
          'travel',
          CategoryKind.expense,
        );
        for (final posting in [
          earned,
          spent,
          erased,
          transfer,
          refund,
          reversal,
        ]) {
          await session.post(posting);
        }
        await session.tombstone(
          PostingTombstone(
            original: erased,
            operation: operation(),
            reason: 'duplicate',
          ),
        );
        final septemberReport = await session.monthlyReport(
          workspace,
          ReportMonth(2026, 9),
        );
        final septemberTwd = septemberReport.currencies.single;
        expect(septemberTwd.currency, twd);
        expect(septemberTwd.income.majorText, '100.00');
        expect(septemberTwd.expense.majorText, '42.00');
        expect(septemberTwd.net.majorText, '58.00');
        expect(septemberTwd.facts.map((row) => row.id).toSet(), {
          earned.id,
          spent.id,
          transfer.id,
        });
        final septemberCategories = {
          for (final row in septemberReport.categories) row.categoryId: row,
        };
        expect(septemberCategories[food]!.expense.majorText, '25.00');
        expect(septemberCategories[travel]!.expense.majorText, '15.00');
        expect(septemberCategories[null]!.expense.majorText, '2.00');
        expect(septemberCategories[null]!.income.majorText, '100.00');
        await session.renameCategory(operation(), food, 1, 'food renamed');
        final afterRename = await session.monthlyReport(
          workspace,
          ReportMonth(2026, 9),
        );
        expect(
          afterRename.categories
              .singleWhere((row) => row.categoryId == food)
              .expense
              .majorText,
          '25.00',
        );
        final octoberReport = await session.monthlyReport(
          workspace,
          ReportMonth(2026, 10),
        );
        final octoberTwd = octoberReport.currencies.single;
        expect(octoberTwd.currency, twd);
        expect(octoberTwd.income.majorText, '-100.00');
        expect(octoberTwd.expense.majorText, '-10.00');
        expect(octoberTwd.net.majorText, '-90.00');
        expect(octoberTwd.facts.map((row) => row.id).toSet(), {
          refund.id,
          reversal.id,
        });
        final octoberCategories = {
          for (final row in octoberReport.categories) row.categoryId: row,
        };
        expect(octoberCategories[food]!.expense.majorText, '-10.00');
        expect(octoberCategories[null]!.income.majorText, '-100.00');
        expect(
          (await session.monthlyReport(
            WorkspaceId(PublicId.generate()),
            ReportMonth(2026, 9),
          )).currencies,
          isEmpty,
        );
      });
      final snapshot = await store.snapshot();
      final restored = open('restored');
      await restored.generations.install(utf8.decode(snapshot), opId());
      await restored.withSession((session) async {
        final report = await session.monthlyReport(
          workspace,
          ReportMonth(2026, 9),
        );
        expect(report.currencies.single.net.majorText, '58.00');
        expect(
          report.categories
              .singleWhere((row) => row.categoryId == food)
              .expense
              .majorText,
          '25.00',
        );
      });
    },
  );

  test('legacy schema without category references still reads uncategorized report', () async {
    final keys = FixtureKeySlots(Directory('${work.path}/legacy-keys'));
    final legacy = LedgerStore(
      Directory('${work.path}/legacy'),
      keys,
      catalogProtection: fixtureCatalogProtection(keys),
    );
    await legacy.initialize(opId());
    await legacy.withSession((session) async {
      await session.createAccount(
        cash,
        Posting.opening(
          id: PublicId.generate(),
          operation: operation(),
          date: cash.openedOn,
          account: ref(cash),
          amount: money(twd, '0'),
        ),
      );
      await session.post(
        Posting.expense(
          id: PublicId.generate(),
          operation: operation(),
          date: BusinessDate(2026, 9, 1),
          account: ref(cash),
          amount: money(twd, '3'),
        ),
      );
      final report = await session.monthlyReport(
        workspace,
        ReportMonth(2026, 9),
      );
      expect(report.currencies.single.expense.majorText, '3.00');
      expect(report.categories.single.categoryId, isNull);
      expect(report.categories.single.expense.majorText, '3.00');
    });
  });
}
