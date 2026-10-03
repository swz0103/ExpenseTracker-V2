import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

final twd = Currency.iso('TWD');
final day = BusinessDate(2026, 10, 1);

Money ntd(int units) => Money(twd, BigInt.from(units));

Matcher fails(FailureKind kind, String diagnostic) =>
    throwsA(AppFailure(kind, diagnostic));

void main() {
  late Directory directory;
  late SqlCipherStore store;
  late LedgerStore ledger;
  late Bookkeeping<SqlBookkeeping> books;
  late PublicId cash;
  final workspace = WorkspaceId(PublicId.generate());

  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('ledger-catalog-');
    store = SqlCipherStore.open(
      File('${directory.path}/ledger.db'),
      StorageKey.random(),
      modules: [ledgerSchema],
    );
    ledger = LedgerStore(store);
    books = Bookkeeping(ledger);
    cash = PublicId.generate();
    await books.openAccount(
      OpenAccount(
        operation: op(),
        accountId: cash,
        name: '現金',
        kind: AccountKind.cash,
        currency: twd,
        openedOn: day,
      ),
    );
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<int> change(CatalogType catalog, CatalogChange change) async {
    final outcome = await books.changeCatalog(
      ChangeCatalog(operation: op(), catalog: catalog, change: change),
    );
    return outcome.value;
  }

  Future<PublicId> category(String name, CategoryKind kind) async {
    final id = PublicId.generate();
    await change(CatalogType.category, CreateEntry(id, name, kind: kind));
    return id;
  }

  Future<PublicId> create(CatalogType type, String name) async {
    final id = PublicId.generate();
    await change(type, CreateEntry(id, name));
    return id;
  }

  int version(PublicId id) =>
      ledger.categories(workspace).singleWhere((c) => c.id == id).version;

  Future<PublicId> spend(
    Money amount, {
    List<CategoryShare> shares = const [],
    List<TagSelection> tags = const [],
    MerchantSelection? merchant,
    CashFlow flow = CashFlow.expense,
  }) async {
    final account = ledger.accounts(workspace).single;
    final outcome = await books.recordCashFlow(
      RecordCashFlow(
        operation: op(),
        postingId: PublicId.generate(),
        flow: flow,
        account: AccountRef(cash, account.rulesVersion),
        date: day,
        amount: amount,
        allocations: shares,
        tags: tags,
        merchant: merchant,
      ),
    );
    return outcome.value;
  }

  test('catalog entries are created, renamed and versioned', () async {
    final food = await category('餐飲', CategoryKind.expense);
    final lunch = PublicId.generate();
    await change(
      CatalogType.category,
      CreateEntry(lunch, '午餐', kind: CategoryKind.expense, parentId: food),
    );
    expect(await change(CatalogType.category, RenameEntry(food, 1, '吃飯')), 2);
    await expectLater(
      change(CatalogType.category, RenameEntry(food, 1, '吃吃')),
      fails(FailureKind.conflict, 'category.versionConflict'),
    );
    await expectLater(
      change(CatalogType.category, ArchiveEntry(food, 2, archived: true)),
      fails(FailureKind.rejected, 'category.hasChildren'),
    );
    final names = {for (final c in ledger.categories(workspace)) c.name};
    expect(names, {'吃飯', '午餐'});
  });

  test('changes that do not fit the catalog are refused', () async {
    await expectLater(
      change(CatalogType.category, CreateEntry(PublicId.generate(), '無類型')),
      fails(FailureKind.rejected, 'catalog.unsupported'),
    );
    final tag = await create(CatalogType.tag, '旅行');
    await expectLater(
      change(CatalogType.tag, MoveCategory(tag, 1, null)),
      fails(FailureKind.rejected, 'catalog.unsupported'),
    );
    await expectLater(
      change(CatalogType.tag, ChangeAlias(tag, 1, '出遊', add: true)),
      fails(FailureKind.rejected, 'catalog.unsupported'),
    );
  });

  test('allocations feed the category report and must add up', () async {
    final food = await category('餐飲', CategoryKind.expense);
    final fun = await category('娛樂', CategoryKind.expense);
    await spend(
      ntd(1000),
      shares: [
        CategoryShare(food, 1, ntd(700)),
        CategoryShare(fun, 1, ntd(300)),
      ],
    );
    final totals = ledger.categoryTotals(workspace, '2026-10');
    expect(totals[(food, 'TWD')]!.expense, ntd(700));
    expect(totals[(fun, 'TWD')]!.expense, ntd(300));
    await expectLater(
      spend(ntd(1000), shares: [CategoryShare(food, 1, ntd(999))]),
      fails(FailureKind.rejected, 'ledger.allocationMismatch'),
    );
  });

  test('categories must be active, current and of the right kind', () async {
    final salary = await category('薪資', CategoryKind.income);
    final food = await category('餐飲', CategoryKind.expense);
    await expectLater(
      spend(ntd(100), shares: [CategoryShare(salary, 1, ntd(100))]),
      fails(FailureKind.rejected, 'category.kindMismatch'),
    );
    await change(CatalogType.category, RenameEntry(food, 1, '吃飯'));
    await expectLater(
      spend(ntd(100), shares: [CategoryShare(food, 1, ntd(100))]),
      fails(FailureKind.conflict, 'category.versionConflict'),
    );
    await change(CatalogType.category, ArchiveEntry(food, 2, archived: true));
    await expectLater(
      spend(ntd(100), shares: [CategoryShare(food, 3, ntd(100))]),
      fails(FailureKind.rejected, 'category.unavailable'),
    );
    final unknown = CategoryShare(PublicId.generate(), 1, ntd(100));
    await expectLater(
      spend(ntd(100), shares: [unknown]),
      fails(FailureKind.notFound, 'category.missing'),
    );
  });

  test('a reversal takes its allocations back out of the report', () async {
    final food = await category('餐飲', CategoryKind.expense);
    final posting = await spend(
      ntd(450),
      shares: [CategoryShare(food, 1, ntd(450))],
    );
    await books.reversePosting(
      ReversePosting(
        operation: op(),
        reversalId: PublicId.generate(),
        originalId: posting,
        date: BusinessDate(2026, 11, 3),
      ),
    );
    expect(
      ledger.categoryTotals(workspace, '2026-10')[(food, 'TWD')]!.expense,
      ntd(450),
    );
    expect(
      ledger.categoryTotals(workspace, '2026-11')[(food, 'TWD')]!.expense,
      ntd(-450),
    );
  });

  test('merged categories report under their target', () async {
    final meals = await category('三餐', CategoryKind.expense);
    final food = await category('餐飲', CategoryKind.expense);
    await spend(ntd(100), shares: [CategoryShare(meals, 1, ntd(100))]);
    await spend(ntd(250), shares: [CategoryShare(food, 1, ntd(250))]);
    final merge = MergeEntry(meals, 1, food, 1);
    expect(await change(CatalogType.category, merge), 2);
    final totals = ledger.categoryTotals(workspace, '2026-10');
    expect(totals.keys, [(food, 'TWD')]);
    expect(totals[(food, 'TWD')]!.expense, ntd(350));
    expect(version(meals), 2);
    expect(version(food), 1);
  });

  test('tags and merchant are stored and checked', () async {
    final trip = await create(CatalogType.tag, '旅行');
    final work = await create(CatalogType.tag, '公司');
    final shop = await create(CatalogType.merchant, '全聯');
    final alias = ChangeAlias(shop, 1, 'PX Mart', add: true);
    await change(CatalogType.merchant, alias);
    final posting = await spend(
      ntd(320),
      tags: [TagSelection(work, 1), TagSelection(trip, 1)],
      merchant: MerchantSelection(shop, 2),
    );
    final metadata = ledger.metadata(posting);
    expect(metadata.tags.toSet(), {trip, work});
    expect(metadata.merchantId, shop);
    expect(ledger.merchants(workspace).single.aliases, ['PX Mart']);

    await change(CatalogType.tag, ArchiveEntry(trip, 1, archived: true));
    await expectLater(
      spend(ntd(1), tags: [TagSelection(trip, 2)]),
      fails(FailureKind.rejected, 'tag.unavailable'),
    );
    await expectLater(
      spend(ntd(1), merchant: MerchantSelection(shop, 1)),
      fails(FailureKind.conflict, 'merchant.versionConflict'),
    );
    await expectLater(
      spend(ntd(1), tags: [TagSelection(work, 1), TagSelection(work, 1)]),
      fails(FailureKind.rejected, 'tag.duplicate'),
    );
  });

  test('a reversal keeps the original tags and merchant', () async {
    final trip = await create(CatalogType.tag, '旅行');
    final shop = await create(CatalogType.merchant, '全聯');
    final posting = await spend(
      ntd(99),
      tags: [TagSelection(trip, 1)],
      merchant: MerchantSelection(shop, 1),
    );
    final reversal = await books.reversePosting(
      ReversePosting(
        operation: op(),
        reversalId: PublicId.generate(),
        originalId: posting,
        date: day,
      ),
    );
    final metadata = ledger.metadata(reversal.value);
    expect(metadata.tags, [trip]);
    expect(metadata.merchantId, shop);
  });
}
