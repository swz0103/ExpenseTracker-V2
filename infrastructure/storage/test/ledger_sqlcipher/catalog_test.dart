import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:domain/accounts.dart';
import 'package:domain/bookkeeping.dart';
import 'package:domain/categories.dart';
import 'package:domain/ledger.dart';
import 'package:storage/ledger_sqlcipher.dart';
import 'package:storage/storage_sqlcipher.dart';
import 'package:test/test.dart';

final twd = Currency.of('TWD');
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
  });

  test('allocations are stored with the entry and must add up', () async {
    final food = await category('餐飲', CategoryKind.expense);
    final fun = await category('娛樂', CategoryKind.expense);
    final posting = await spend(
      ntd(1000),
      shares: [
        CategoryShare(food, 1, ntd(700)),
        CategoryShare(fun, 1, ntd(300)),
      ],
    );
    final amounts = {
      for (final allocation in ledger.postingById(posting)!.allocations)
        allocation.categoryId: allocation.amount,
    };
    expect(amounts[food], ntd(700));
    expect(amounts[fun], ntd(300));
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

  test('a merged category points at its target', () async {
    final meals = await category('三餐', CategoryKind.expense);
    final food = await category('餐飲', CategoryKind.expense);
    await spend(ntd(100), shares: [CategoryShare(meals, 1, ntd(100))]);
    await spend(ntd(250), shares: [CategoryShare(food, 1, ntd(250))]);
    final merge = MergeEntry(meals, 1, food, 1);
    expect(await change(CatalogType.category, merge), 2);
    final categories = ledger.categories(workspace);
    final merged = categories.singleWhere((c) => c.id == meals);
    expect(merged.replacementId, food);
    expect(version(meals), 2);
    expect(version(food), 1);
  });

  test('tags and merchant are stored and checked', () async {
    final trip = await create(CatalogType.tag, '旅行');
    final work = await create(CatalogType.tag, '公司');
    final shop = await create(CatalogType.merchant, '全聯');
    await change(CatalogType.merchant, RenameEntry(shop, 1, '全聯福利中心'));
    final posting = await spend(
      ntd(320),
      tags: [TagSelection(work, 1), TagSelection(trip, 1)],
      merchant: MerchantSelection(shop, 2),
    );
    final metadata = ledger.metadata(posting);
    expect(metadata.tags.toSet(), {trip, work});
    expect(metadata.merchantId, shop);
    expect(ledger.merchants(workspace).single.name, '全聯福利中心');

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
    final reversal = await books.deletePosting(
      DeletePosting(
        operation: op(),
        reversalId: PublicId.generate(),
        originalId: posting,
      ),
    );
    final metadata = ledger.metadata(reversal.value);
    expect(metadata.tags, [trip]);
    expect(metadata.merchantId, shop);
  });
}
