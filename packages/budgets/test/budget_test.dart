import 'package:budgets/budgets.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:reports/reports.dart';
import 'package:test/test.dart';

void main() {
  final space = WorkspaceId(PublicId.generate());
  final otherSpace = WorkspaceId(PublicId.generate());
  final twd = Currency('TWD', 2);
  final usd = Currency('USD', 2);
  final account = PublicId.generate();
  final otherAccount = PublicId.generate();
  final tag = PublicId.generate();
  final food = PublicId.generate();
  final groceries = PublicId.generate();
  final travel = PublicId.generate();
  final catalog = CategoryCatalog.restore(space, [
    Category.restore(
      id: food,
      workspace: space,
      name: 'Food',
      kind: CategoryKind.expense,
      version: 1,
    ),
    Category.restore(
      id: groceries,
      workspace: space,
      name: 'Groceries',
      kind: CategoryKind.expense,
      version: 1,
      parentId: food,
    ),
    Category.restore(
      id: travel,
      workspace: space,
      name: 'Travel',
      kind: CategoryKind.expense,
      version: 1,
    ),
  ]);
  BudgetFact row({
    required PostingKind kind,
    required Currency currency,
    required String expense,
    required BusinessDate date,
    PublicId? accountId,
    List<CategoryAllocation> allocations = const [],
    Set<PublicId> tags = const {},
    WorkspaceId? workspace,
    PublicId? id,
  }) => BudgetFact(
    workspace: workspace ?? space,
    tagIds: tags,
    report: MonthlyFact(
      id: id ?? PublicId.generate(),
      date: date,
      kind: kind,
      income: Money(currency, BigInt.zero),
      expense: Money.parse(currency, expense),
      accountId: accountId,
      allocations: allocations,
    ),
  );
  final day = BusinessDate(2026, 9, 29);

  test('signed spending uses report effects, never transfer principal', () {
    final facts = [
      row(kind: PostingKind.opening, currency: twd, expense: '0', date: day),
      row(
        kind: PostingKind.expense,
        currency: twd,
        expense: '100',
        date: day,
        allocations: [
          CategoryAllocation(groceries, Money.parse(twd, '60')),
          CategoryAllocation(travel, Money.parse(twd, '40')),
        ],
      ),
      row(
        kind: PostingKind.refund,
        currency: twd,
        expense: '-10',
        date: day,
        allocations: [CategoryAllocation(groceries, Money.parse(twd, '10'))],
      ),
      row(kind: PostingKind.transfer, currency: twd, expense: '2', date: day),
      row(kind: PostingKind.transfer, currency: twd, expense: '0', date: day),
    ];
    final all = evaluateBudget(
      BudgetPlan(
        id: PublicId.generate(),
        workspace: space,
        month: ReportMonth(2026, 9),
        limit: Money.parse(twd, '100'),
      ),
      facts,
      categories: catalog,
    );
    expect(all.spent.majorText, '92.00');
    expect(all.remaining.majorText, '8.00');
    expect(all.atWarning, isTrue);
    expect(all.overLimit, isFalse);

    final parent = evaluateBudget(
      BudgetPlan(
        id: PublicId.generate(),
        workspace: space,
        month: ReportMonth(2026, 9),
        limit: Money.parse(twd, '50'),
        categoryId: food,
      ),
      facts,
      categories: catalog,
    );
    expect(parent.spent.majorText, '50.00');
    expect(parent.remaining.majorText, '0.00');
  });

  test('account, tag and category dimensions combine without FX guessing', () {
    final facts = [
      row(
        kind: PostingKind.expense,
        currency: twd,
        expense: '20',
        date: day,
        accountId: account,
        tags: {tag},
        allocations: [CategoryAllocation(groceries, Money.parse(twd, '20'))],
      ),
      row(
        kind: PostingKind.expense,
        currency: twd,
        expense: '30',
        date: day,
        accountId: otherAccount,
        tags: {tag},
        allocations: [CategoryAllocation(groceries, Money.parse(twd, '30'))],
      ),
      row(
        kind: PostingKind.expense,
        currency: twd,
        expense: '40',
        date: day,
        accountId: account,
        allocations: [CategoryAllocation(groceries, Money.parse(twd, '40'))],
      ),
      row(
        kind: PostingKind.expense,
        currency: usd,
        expense: '5',
        date: day,
        accountId: account,
        tags: {tag},
        allocations: [CategoryAllocation(groceries, Money.parse(usd, '5'))],
      ),
    ];
    final result = evaluateBudget(
      BudgetPlan(
        id: PublicId.generate(),
        workspace: space,
        month: ReportMonth(2026, 9),
        limit: Money.parse(twd, '25'),
        categoryId: food,
        accountIds: {account},
        tagIds: {tag},
      ),
      facts,
      categories: catalog,
    );
    expect(result.spent.majorText, '20.00');
    expect(result.otherCurrencyFacts, 1);
    expect(result.atWarning, isTrue);
  });

  test('wrong workspace, month and duplicate facts fail closed', () {
    final plan = BudgetPlan(
      id: PublicId.generate(),
      workspace: space,
      month: ReportMonth(2026, 9),
      limit: Money.parse(twd, '10'),
    );
    final item = row(
      kind: PostingKind.expense,
      currency: twd,
      expense: '2',
      date: day,
    );
    expect(
      () => evaluateBudget(plan, [item, item], categories: catalog),
      throwsFormatException,
    );
    expect(
      () => evaluateBudget(plan, [
        row(
          kind: PostingKind.expense,
          currency: twd,
          expense: '2',
          date: day,
          workspace: otherSpace,
        ),
      ], categories: catalog),
      throwsFormatException,
    );
    expect(
      () => evaluateBudget(plan, [
        row(
          kind: PostingKind.expense,
          currency: twd,
          expense: '2',
          date: BusinessDate(2026, 10, 1),
        ),
      ], categories: catalog),
      throwsFormatException,
    );
  });

  test('over-refund stays signed and arithmetic overflow is rejected', () {
    final plan = BudgetPlan(
      id: PublicId.generate(),
      workspace: space,
      month: ReportMonth(2026, 9),
      limit: Money.parse(twd, '100'),
    );
    final result = evaluateBudget(plan, [
      row(kind: PostingKind.refund, currency: twd, expense: '-5', date: day),
    ], categories: catalog);
    expect(result.spent.majorText, '-5.00');
    expect(result.remaining.majorText, '105.00');
    expect(result.atWarning, isFalse);

    final nearMax = BudgetPlan(
      id: PublicId.generate(),
      workspace: space,
      month: ReportMonth(2026, 9),
      limit: Money(twd, Money.maxMinorUnits),
    );
    expect(
      () => evaluateBudget(nearMax, [
        row(kind: PostingKind.refund, currency: twd, expense: '-1', date: day),
      ], categories: catalog),
      throwsA(isA<MoneyException>()),
    );
  });
}
