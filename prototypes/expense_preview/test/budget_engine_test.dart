import 'dart:io';

import 'package:budgets/budgets.dart';
import 'package:categories/categories.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:reports/reports.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/budget-engine-tests')
    ..createSync(recursive: true);

  test(
    'monthly budget reads effective saved Ledger tags, categories and refunds',
    () async {
      final work = root.createTempSync('case-');
      final vault = MemoryVault();
      var engine = engineAt(work, vault, schemaVersion: 14);
      try {
        await setup(engine);
        final a = account(engine);
        await engine.createAccount(a, opening(a));
        OperationKey op() =>
            OperationKey(engine.workspace, OperationId(PublicId.generate()));
        final food = PublicId.generate();
        final groceries = PublicId.generate();
        final tag = PublicId.generate();
        final otherTag = PublicId.generate();
        await engine.createCategory(op(), food, 'Food', CategoryKind.expense);
        await engine.createCategory(
          op(),
          groceries,
          'Groceries',
          CategoryKind.expense,
          parentId: food,
        );
        await engine.createTag(op(), tag, 'Essential');
        await engine.createTag(op(), otherTag, 'Other');
        final spent = Posting.expense(
          id: PublicId.generate(),
          operation: op(),
          date: BusinessDate(2026, 9, 29),
          account: ref(a),
          amount: Money.parse(a.currency, '40'),
          allocations: [
            Allocation(
              groceries,
              Money.parse(a.currency, '40'),
              expectedCategoryVersion: 1,
            ),
          ],
        );
        await engine.post(spent, tags: [TagSelection(tag, 1)]);
        await engine.post(
          Posting.expense(
            id: PublicId.generate(),
            operation: op(),
            date: BusinessDate(2026, 9, 29),
            account: ref(a),
            amount: Money.parse(a.currency, '5'),
          ),
        );
        final refund = Posting.refund(
          id: PublicId.generate(),
          operation: op(),
          date: BusinessDate(2026, 10, 1),
          account: ref(a),
          originalId: spent.id,
          amount: Money.parse(a.currency, '10'),
          allocations: [
            Allocation(
              groceries,
              Money.parse(a.currency, '10'),
              expectedCategoryVersion: 1,
            ),
          ],
        );
        await engine.post(refund, tags: [TagSelection(tag, 1)]);

        BudgetPlan plan(int month, {Set<PublicId> tags = const {}}) =>
            BudgetPlan(
              id: PublicId.generate(),
              workspace: engine.workspace,
              month: ReportMonth(2026, month),
              limit: Money.parse(a.currency, '50'),
              categoryId: food,
              accountIds: {a.id},
              tagIds: tags,
            );
        final september = await engine.evaluateMonthlyBudget(
          plan(9, tags: {tag}),
        );
        expect(september.spent.majorText, '40.00');
        expect(september.atWarning, isTrue);
        expect(
          (await engine.evaluateMonthlyBudget(plan(9, tags: {otherTag})))
              .spent
              .majorText,
          '0.00',
        );
        expect(
          (await engine.evaluateMonthlyBudget(plan(10, tags: {tag})))
              .spent
              .majorText,
          '-10.00',
        );
        await expectLater(
          engine.evaluateMonthlyBudget(
            BudgetPlan(
              id: PublicId.generate(),
              workspace: WorkspaceId(PublicId.generate()),
              month: ReportMonth(2026, 9),
              limit: Money.parse(a.currency, '50'),
            ),
          ),
          throwsA(isA<PreviewInvalid>()),
        );

        await engine.lock();
        engine = engineAt(work, vault, schemaVersion: 14);
        await engine.unlock(password);
        expect(
          (await engine.evaluateMonthlyBudget(plan(9, tags: {tag})))
              .spent
              .majorText,
          '40.00',
        );
      } finally {
        await engine.lock();
        deleteSynthetic(work, root);
      }
    },
  );
}
