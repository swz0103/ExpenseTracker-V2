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
  final root = Directory('.dart_tool/search-session-tests')
    ..createSync(recursive: true);
  final twd = Currency('TWD', 2);
  final day = BusinessDate(2026, 9, 28);
  late Directory work;
  late WorkspaceId workspace;
  late Account source, destination;
  late PublicId category, tag, merchant;
  late Posting expense, smaller, transfer;
  late LedgerStore store;

  OperationId operationId() => OperationId(PublicId.generate());
  OperationKey operation() => OperationKey(workspace, operationId());
  Money money(String text) => Money.parse(twd, text);
  PostingAccount ref(Account account) => PostingAccount(
    id: account.id,
    workspace: workspace,
    currency: twd,
    expectedVersion: account.version,
  );
  LedgerStore openStore(String name) {
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
    store = openStore('source');
    await store.initialize(operationId());
    source = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'source',
      kind: AccountKind.cash,
      currency: twd,
      openedOn: BusinessDate(2026, 1, 1),
    );
    destination = Account.open(
      id: PublicId.generate(),
      workspace: workspace,
      name: 'destination',
      kind: AccountKind.bank,
      currency: twd,
      openedOn: BusinessDate(2026, 1, 1),
    );
    category = PublicId.generate();
    tag = PublicId.generate();
    merchant = PublicId.generate();
    expense = Posting.expense(
      id: PublicId.generate(),
      operation: operation(),
      date: day,
      account: ref(source),
      amount: money('12.50'),
      allocations: [
        Allocation(category, money('12.50'), expectedCategoryVersion: 1),
      ],
    );
    smaller = Posting.expense(
      id: PublicId.generate(),
      operation: operation(),
      date: day,
      account: ref(source),
      amount: money('5.00'),
    );
    transfer = Posting.transfer(
      id: PublicId.generate(),
      operation: operation(),
      date: day,
      source: ref(source),
      destination: ref(destination),
      principal: money('3.00'),
    );
    await store.withSession((session) async {
      for (final account in [source, destination]) {
        await session.createAccount(
          account,
          Posting.opening(
            id: PublicId.generate(),
            operation: operation(),
            date: account.openedOn,
            account: ref(account),
            amount: money('100'),
          ),
        );
      }
      await session.createCategory(
        operation(),
        category,
        'food',
        CategoryKind.expense,
      );
      await session.createTag(operation(), tag, 'trip');
      await session.createMerchant(operation(), merchant, 'cafe');
      await session.post(
        expense,
        tags: [TagSelection(tag, 1)],
        merchant: MerchantSelection(merchant, 1),
      );
      await session.post(smaller);
      await session.post(transfer);
      await session.reviseNote(
        operation(),
        NoteChange(expense.id, 0, 'Cafe lunch'),
      );
    });
  });
  tearDown(() {
    if (!work.resolveSymbolicLinksSync().startsWith(
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}',
    )) {
      throw StateError('Unsafe cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test(
    'AND filters use current references and exact inclusive ranges',
    () async {
      await store.withSession((session) async {
        final query = LedgerSearchQuery(
          from: day,
          through: day,
          accountId: source.id,
          categoryId: category,
          tagId: tag,
          merchantId: merchant,
          currency: twd,
          kind: PostingKind.expense,
          minAbsAmount: money('12.50'),
          maxAbsAmount: money('12.50'),
          noteContains: 'CAFE',
        );
        expect(
          (await session.searchEntries(workspace, query)).single.id,
          expense.id,
        );
        expect(
          await session.searchEntries(WorkspaceId(PublicId.generate()), query),
          isEmpty,
        );
        expect(
          (await session.searchEntries(
            workspace,
            LedgerSearchQuery(
              accountId: destination.id,
              kind: PostingKind.transfer,
            ),
          )).single.id,
          transfer.id,
        );
        expect(
          (await session.searchEntries(
            workspace,
            LedgerSearchQuery(
              currency: twd,
              maxAbsAmount: money('5.00'),
              kind: PostingKind.expense,
            ),
          )).single.id,
          smaller.id,
        );
        await session.reviseNote(
          operation(),
          NoteChange(expense.id, 1, 'Dinner'),
        );
        expect(await session.searchEntries(workspace, query), isEmpty);
        expect(
          (await session.searchEntries(
            workspace,
            LedgerSearchQuery(noteContains: 'Dinner'),
          )).single.id,
          expense.id,
        );
      });
    },
  );

  test(
    'keyset, tombstone, and portable restore preserve effective search',
    () async {
      await store.withSession((session) async {
        final query = LedgerSearchQuery(from: day, through: day);
        final ids = <PublicId>[];
        LedgerEntry? before;
        while (true) {
          final page = await session.searchEntries(
            workspace,
            query,
            before: before,
            limit: 1,
          );
          if (page.isEmpty) break;
          ids.add(page.single.id);
          before = page.single;
        }
        expect(ids.toSet(), {expense.id, smaller.id, transfer.id});
        expect(ids, hasLength(3));
        expect(
          () => session.searchEntries(workspace, query, limit: 0),
          throwsA(isA<ArgumentError>()),
        );
        await session.tombstone(
          PostingTombstone(
            original: smaller,
            operation: operation(),
            reason: 'duplicate',
          ),
        );
        expect(
          (await session.searchEntries(
            workspace,
            query,
          )).map((e) => e.id).toSet(),
          {expense.id, transfer.id},
        );
      });
      final saved = await store.snapshot();
      final restored = openStore('restored');
      await restored.generations.install(utf8.decode(saved), operationId());
      await restored.withSession((session) async {
        expect(
          (await session.searchEntries(
            workspace,
            LedgerSearchQuery(from: day, through: day),
          )).map((e) => e.id).toSet(),
          {expense.id, transfer.id},
        );
      });
    },
  );

  test('full 5000-event book keeps filtered search and keyset exact', () async {
    await store.withSession((session) async {
      // Two openings and three existing events were created in setUp.
      for (var i = 0; i < 4995; i++) {
        await session.post(
          Posting.income(
            id: PublicId.generate(),
            operation: operation(),
            date: day,
            account: ref(source),
            amount: money('1.00'),
          ),
        );
      }
      final filtered = await session.searchEntries(
        workspace,
        LedgerSearchQuery(
          categoryId: category,
          tagId: tag,
          merchantId: merchant,
          noteContains: 'CAFE',
          kind: PostingKind.expense,
          currency: twd,
          minAbsAmount: money('12.50'),
        ),
      );
      expect(filtered.map((row) => row.id), [expense.id]);
      final seen = <PublicId>{};
      LedgerEntry? before;
      while (true) {
        final page = await session.searchEntries(
          workspace,
          LedgerSearchQuery(),
          before: before,
        );
        if (page.isEmpty) break;
        for (final row in page) {
          expect(seen.add(row.id), isTrue);
        }
        before = page.last;
      }
      expect(seen, hasLength(5000));
      final report = await session.monthlyReport(
        workspace,
        ReportMonth(2026, 9),
      );
      final twdSummary = report.currencies.single;
      expect(twdSummary.income.majorText, '4995.00');
      expect(twdSummary.expense.majorText, '17.50');
      expect(twdSummary.net.majorText, '4977.50');
      expect(twdSummary.facts, hasLength(4997));
    });
  }, timeout: const Timeout(Duration(minutes: 10)));

  test(
    'unsupported reference filter fails rather than widening results',
    () async {
      final old = LedgerStore(
        Directory('${work.path}/old'),
        FixtureKeySlots(Directory('${work.path}/old-keys')),
      );
      await old.initialize(operationId());
      await old.withSession((session) async {
        await expectLater(
          session.searchEntries(workspace, LedgerSearchQuery(tagId: tag)),
          throwsUnsupportedError,
        );
        expect(
          await session.searchEntries(workspace, LedgerSearchQuery()),
          isEmpty,
        );
      });
    },
  );
}
