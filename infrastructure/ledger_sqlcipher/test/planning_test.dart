import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:app_core/app_core.dart';
import 'package:bookkeeping/bookkeeping.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_sqlcipher/ledger_sqlcipher.dart';
import 'package:recurring_transactions/recurring_transactions.dart';
import 'package:reports/reports.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';
import 'package:test/test.dart';

final twd = Currency.of('TWD');
final october = ReportMonth(2026, 10);

Money ntd(int units) => Money(twd, BigInt.from(units));

Matcher fails(FailureKind kind, String diagnostic) =>
    throwsA(AppFailure(kind, diagnostic));

void main() {
  late Directory directory;
  late SqlCipherStore store;
  late LedgerStore ledger;
  late Bookkeeping<SqlBookkeeping> books;
  late PlanningBook<SqlBookkeeping> planning;
  late PublicId cash;
  final workspace = WorkspaceId(PublicId.generate());

  OperationKey op() =>
      OperationKey(workspace, OperationId(PublicId.generate()));

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('ledger-planning-');
    store = SqlCipherStore.open(
      File('${directory.path}/ledger.db'),
      StorageKey.random(),
      modules: [ledgerSchema],
    );
    ledger = LedgerStore(store);
    books = Bookkeeping(ledger);
    planning = PlanningBook(books);
    cash = PublicId.generate();
    await books.openAccount(
      OpenAccount(
        operation: op(),
        accountId: cash,
        name: '現金',
        kind: AccountKind.cash,
        currency: twd,
        openedOn: BusinessDate(2026, 1, 1),
      ),
    );
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Future<PublicId> category(String name) async {
    final id = PublicId.generate();
    await books.changeCatalog(
      ChangeCatalog(
        operation: op(),
        catalog: CatalogType.category,
        change: CreateEntry(id, name, kind: CategoryKind.expense),
      ),
    );
    return id;
  }

  Future<void> spend(int units, PublicId category) => books.recordCashFlow(
    RecordCashFlow(
      operation: op(),
      postingId: PublicId.generate(),
      flow: CashFlow.expense,
      account: AccountRef(cash, 1),
      date: BusinessDate(2026, 10, 9),
      amount: ntd(units),
      allocations: [CategoryShare(category, 1, ntd(units))],
    ),
  );

  test('a budget follows spending in its category', () async {
    final food = await category('餐飲');
    final lunch = await category('午餐');
    final fun = await category('娛樂');
    final budget = PublicId.generate();
    expect(
      (await planning.setBudget(
        SetBudget(
          operation: op(),
          budgetId: budget,
          expectedVersion: 0,
          month: october,
          limit: ntd(5000),
          categoryId: food,
        ),
      )).value,
      1,
    );
    await spend(3000, food);
    await spend(1000, fun);
    var status = ledger.budgetStatus(workspace, october).single;
    expect(status.spent, ntd(3000));
    expect(status.atWarning, isFalse);

    await spend(1200, lunch);
    await books.changeCatalog(
      ChangeCatalog(
        operation: op(),
        catalog: CatalogType.category,
        change: MergeEntry(lunch, 1, food, 1),
      ),
    );
    status = ledger.budgetStatus(workspace, october).single;
    expect(status.spent, ntd(4200));
    expect(status.atWarning, isTrue);
    expect(status.overLimit, isFalse);

    await expectLater(
      planning.setBudget(
        SetBudget(
          operation: op(),
          budgetId: budget,
          expectedVersion: 0,
          month: october,
          limit: ntd(1),
        ),
      ),
      fails(FailureKind.conflict, 'budget.versionConflict'),
    );
  });

  test('recurring templates propose, confirm once and stop', () async {
    final rent = PublicId.generate();
    Future<void> save(int expected, {bool active = true}) =>
        planning.saveRecurring(
          SaveRecurring(
            operation: op(),
            templateId: rent,
            expectedVersion: expected,
            accountId: cash,
            label: '房租',
            amount: ntd(-12000),
            firstDate: BusinessDate(2026, 8, 5),
            unit: RecurrenceUnit.month,
            every: 1,
            active: active,
          ),
        );
    Future<void> confirm(BusinessDate due, {int version = 1}) =>
        planning.confirm(
          ConfirmRecurring(
            operation: op(),
            postingId: PublicId.generate(),
            templateId: rent,
            expectedTemplateVersion: version,
            dueDate: due,
            account: AccountRef(cash, 1),
          ),
        );
    List<BusinessDate> due() => [
      for (final candidate in ledger.dueRecurring(
        workspace,
        after: BusinessDate(2026, 7, 31),
        through: BusinessDate(2026, 10, 31),
      ))
        candidate.dueDate,
    ];

    await save(0);
    expect(due(), [
      BusinessDate(2026, 8, 5),
      BusinessDate(2026, 9, 5),
      BusinessDate(2026, 10, 5),
    ]);
    await confirm(BusinessDate(2026, 8, 5));
    expect(due(), hasLength(2));
    expect(ledger.balance(ledger.accounts(workspace).single), ntd(-12000));
    await expectLater(
      confirm(BusinessDate(2026, 8, 5)),
      fails(FailureKind.conflict, 'recurring.confirmed'),
    );
    await expectLater(
      confirm(BusinessDate(2026, 8, 6)),
      fails(FailureKind.rejected, 'recurring.not-due'),
    );
    await save(1, active: false);
    expect(due(), isEmpty);
    await expectLater(
      confirm(BusinessDate(2026, 9, 5), version: 2),
      fails(FailureKind.rejected, 'recurring.stopped'),
    );
  });

  test('deleting a confirmed entry opens its due date again', () async {
    final gym = PublicId.generate();
    await planning.saveRecurring(
      SaveRecurring(
        operation: op(),
        templateId: gym,
        expectedVersion: 0,
        accountId: cash,
        label: '健身房',
        amount: ntd(-990),
        firstDate: BusinessDate(2026, 9, 1),
        unit: RecurrenceUnit.month,
        every: 1,
      ),
    );
    Future<PublicId> confirm() async {
      final outcome = await planning.confirm(
        ConfirmRecurring(
          operation: op(),
          postingId: PublicId.generate(),
          templateId: gym,
          expectedTemplateVersion: 1,
          dueDate: BusinessDate(2026, 9, 1),
          account: AccountRef(cash, 1),
        ),
      );
      return outcome.value;
    }

    bool open() => ledger
        .dueRecurring(
          workspace,
          after: BusinessDate(2026, 8, 31),
          through: BusinessDate(2026, 9, 30),
        )
        .isNotEmpty;

    final first = await confirm();
    expect(open(), isFalse);
    await books.deletePosting(
      DeletePosting(
        operation: op(),
        reversalId: PublicId.generate(),
        originalId: first,
      ),
    );
    expect(open(), isTrue);
    final second = await confirm();
    expect(second, isNot(first));
    expect(open(), isFalse);
    expect(ledger.balance(ledger.accounts(workspace).single), ntd(-990));
  });
}
