import 'dart:convert';

import 'package:accounts/accounts.dart';
import 'package:categories/categories.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/categories_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:modular_persistence_probe/workflows.dart';

/// Synthetic fixture only, shared by host persistence and encrypted-stage tests.
/// This is not initialization data for the product.
final class AllocationFixture {
  AllocationFixture(this.db);
  final ProbeDatabase db;
  final ws = WorkspaceId(PublicId.generate());
  final currency = Currency('USD', 2);
  final food = PublicId.generate(),
      travel = PublicId.generate(),
      salary = PublicId.generate();
  late final Account account = Account.open(
    id: PublicId.generate(),
    workspace: ws,
    name: '合成帳戶',
    kind: AccountKind.cash,
    currency: currency,
    openedOn: BusinessDate(2026, 1, 1),
  );
  PostingAccount get reference => PostingAccount(
    id: account.id,
    workspace: ws,
    currency: currency,
    expectedVersion: 1,
  );
  OperationKey operation() =>
      OperationKey(ws, OperationId(PublicId.generate()));
  Money money(String value) => Money.parse(currency, value);
  Future<void> initialize() async {
    await FinancialWorkflows(db).createAccount(
      account,
      Posting.opening(
        id: PublicId.generate(),
        operation: operation(),
        date: account.openedOn,
        account: reference,
        amount: money('100'),
      ),
    );
    final adapter = CategoriesAdapter(db);
    await adapter.mutate(
      operation(),
      CategoryMutation.create(food, '飲食', CategoryKind.expense),
    );
    await adapter.mutate(
      operation(),
      CategoryMutation.create(travel, '交通', CategoryKind.expense),
    );
    await adapter.mutate(
      operation(),
      CategoryMutation.create(salary, '薪資', CategoryKind.income),
    );
  }

  Posting expense({
    String amount = '10',
    int? version = 1,
    List<Allocation>? allocations,
    OperationKey? op,
  }) => Posting.expense(
    id: PublicId.generate(),
    operation: op ?? operation(),
    date: BusinessDate(2026, 9, 27),
    account: reference,
    amount: money(amount),
    allocations:
        allocations ??
        [Allocation(food, money(amount), expectedCategoryVersion: version)],
  );
  Posting income() => Posting.income(
    id: PublicId.generate(),
    operation: operation(),
    date: BusinessDate(2026, 9, 27),
    account: reference,
    amount: money('20'),
    allocations: [Allocation(salary, money('20'), expectedCategoryVersion: 1)],
  );
}

StorageBinding allocationBinding() => StorageBinding(
  PublicId.generate(),
  PublicId.generate(),
  OperationId(PublicId.generate()),
  'c' * 64,
);

Future<String> allocationState(ProbeDatabase db) async => jsonEncode({
  for (final table in [
    'accounts',
    'events',
    'legs',
    'openings',
    'allocations',
    'receipts',
    'audit',
    'categories',
    'category_changes',
  ])
    table: [
      for (final row
          in await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
        row.data,
    ],
});
