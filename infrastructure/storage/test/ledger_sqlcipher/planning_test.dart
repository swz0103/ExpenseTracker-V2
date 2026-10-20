import 'dart:io';

import 'package:core/app_core.dart';
import 'package:core/foundation_values.dart';
import 'package:domain/accounts.dart';
import 'package:domain/bookkeeping.dart';
import 'package:domain/categories.dart';
import 'package:domain/recurring_transactions.dart';
import 'package:domain/reports.dart';
import 'package:storage/ledger_sqlcipher.dart';
import 'package:storage/storage_sqlcipher.dart';
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

  test('a budget is stored with its version', () async {
    final food = await category('餐飲');
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
    final plan = ledger.budgetPlans(workspace).single;
    expect(plan.id, budget);
    expect(plan.categoryId, food);
    expect(plan.limit, ntd(5000));
    expect(plan.version, 1);

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

  test('a removed budget is gone', () async {
    final food = await category('餐飲');
    final budget = PublicId.generate();
    await planning.setBudget(
      SetBudget(
        operation: op(),
        budgetId: budget,
        expectedVersion: 0,
        month: october,
        limit: ntd(5000),
        categoryId: food,
        repeats: true,
      ),
    );
    expect(ledger.budgetPlans(workspace), hasLength(1));
    await expectLater(
      planning.removeBudget(
        RemoveBudget(operation: op(), budgetId: budget, expectedVersion: 2),
      ),
      fails(FailureKind.conflict, 'budget.versionConflict'),
    );
    await planning.removeBudget(
      RemoveBudget(operation: op(), budgetId: budget, expectedVersion: 1),
    );
    expect(ledger.budgetPlans(workspace), isEmpty);
    await expectLater(
      planning.removeBudget(
        RemoveBudget(operation: op(), budgetId: budget, expectedVersion: 1),
      ),
      fails(FailureKind.notFound, 'budget.not-found'),
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
    final listed = ledger.recurringTemplates(workspace).single;
    expect((listed.$1.label, listed.$2), ('房租', true));
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
    expect(ledger.recurringTemplates(workspace).single.$2, isFalse);
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

  test('a repeating budget is stored as repeating', () async {
    final food = await category('餐飲');
    Future<void> budget(PublicId id, {required bool repeats}) async {
      await planning.setBudget(
        SetBudget(
          operation: op(),
          budgetId: id,
          expectedVersion: 0,
          month: october,
          limit: ntd(8000),
          categoryId: food,
          repeats: repeats,
        ),
      );
    }

    final monthly = PublicId.generate();
    await budget(monthly, repeats: true);
    await budget(PublicId.generate(), repeats: false);
    final plans = ledger.budgetPlans(workspace);
    expect(plans, hasLength(2));
    final repeating = plans.singleWhere((plan) => plan.repeats);
    expect(repeating.id, monthly);
    expect(repeating.forMonth(ReportMonth(2026, 12)).month.month, 12);
  });

  test('a confirmation takes the real amount and keeps its date', () async {
    final power = await category('電費');
    final bill = PublicId.generate();
    await planning.saveRecurring(
      SaveRecurring(
        operation: op(),
        templateId: bill,
        expectedVersion: 0,
        accountId: cash,
        label: '電費',
        amount: ntd(-1500),
        firstDate: BusinessDate(2026, 10, 5),
        unit: RecurrenceUnit.month,
        every: 2,
        categoryId: power,
      ),
    );
    final outcome = await planning.confirm(
      ConfirmRecurring(
        operation: op(),
        postingId: PublicId.generate(),
        templateId: bill,
        expectedTemplateVersion: 1,
        dueDate: BusinessDate(2026, 10, 5),
        account: AccountRef(cash, 1),
        amount: ntd(1832),
        date: BusinessDate(2026, 10, 7),
        allocations: [CategoryShare(power, 1, ntd(1832))],
      ),
    );
    final allocation = ledger.postingById(outcome.value)!.allocations.single;
    expect(allocation.categoryId, power);
    expect(allocation.amount, ntd(1832));

    // Correcting the amount keeps the due date confirmed.
    await books.correctCashFlow(
      CorrectCashFlow(
        operation: op(),
        replacementId: PublicId.generate(),
        originalId: outcome.value,
        reversalId: PublicId.generate(),
        account: AccountRef(cash, 1),
        date: BusinessDate(2026, 10, 7),
        amount: ntd(1830),
        allocations: [CategoryShare(power, 1, ntd(1830))],
      ),
    );
    final open = ledger.dueRecurring(
      workspace,
      after: BusinessDate(2026, 9, 30),
      through: BusinessDate(2026, 10, 31),
    );
    expect(open, isEmpty);
    expect(ledger.balance(ledger.accounts(workspace).single), ntd(-1830));
  });

  test('every planning refusal names its reason and changes nothing', () async {
    // Health check G5-06: a refused command writes no event and leaves
    // every projection row as it was.
    Future<void> rejects(
      Future<Object?> Function() command,
      FailureKind kind,
      String code,
    ) async {
      final events = store.eventCount;
      final rows = projectionRows(store);
      await expectLater(command(), fails(kind, code));
      expect(store.eventCount, events);
      expect(projectionRows(store), rows);
    }

    final salary = PublicId.generate();
    await books.changeCatalog(
      ChangeCatalog(
        operation: op(),
        catalog: CatalogType.category,
        change: CreateEntry(salary, '薪水', kind: CategoryKind.income),
      ),
    );
    SetBudget budget({required int limit, PublicId? categoryId}) {
      return SetBudget(
        operation: op(),
        budgetId: PublicId.generate(),
        expectedVersion: 0,
        month: october,
        limit: ntd(limit),
        categoryId: categoryId,
      );
    }

    SaveRecurring template({
      int expectedVersion = 0,
      int every = 1,
      Money? amount,
    }) {
      return SaveRecurring(
        operation: op(),
        templateId: PublicId.generate(),
        expectedVersion: expectedVersion,
        accountId: cash,
        label: '房租',
        amount: amount ?? ntd(-12000),
        firstDate: BusinessDate(2026, 10, 5),
        unit: RecurrenceUnit.month,
        every: every,
      );
    }

    await rejects(
      () => planning.setBudget(budget(limit: 0)),
      FailureKind.rejected,
      'budget.invalid',
    );
    await rejects(
      () => planning.setBudget(budget(limit: 5000, categoryId: salary)),
      FailureKind.rejected,
      'budget.category-kind',
    );
    await rejects(
      () => planning.saveRecurring(template(expectedVersion: 2)),
      FailureKind.conflict,
      'recurring.versionConflict',
    );
    await rejects(
      () => planning.saveRecurring(
        template(amount: Money(Currency.of('USD'), BigInt.from(-100))),
      ),
      FailureKind.rejected,
      'recurring.account',
    );
    await rejects(
      () => planning.saveRecurring(template(every: 0)),
      FailureKind.rejected,
      'recurring.invalid',
    );
    await rejects(
      () => books.openAccount(
        OpenAccount(
          operation: op(),
          accountId: cash,
          name: '另一個現金',
          kind: AccountKind.cash,
          currency: twd,
          openedOn: BusinessDate(2026, 1, 1),
        ),
      ),
      FailureKind.conflict,
      'account.exists',
    );
  });
}
