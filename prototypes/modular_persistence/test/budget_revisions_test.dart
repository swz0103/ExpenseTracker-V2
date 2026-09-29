import 'dart:io';

import 'package:budgets/budgets.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:modular_persistence_probe/budget_revisions_adapter.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:modular_persistence_probe/fixture_allocation.dart'
    show allocationBinding;
import 'package:modular_persistence_probe/storage_binding.dart';
import 'package:reports/reports.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/budget-revisions-tests')
    ..createSync(recursive: true);
  late Directory work;
  late File file;
  late ProbeDatabase db;
  late StorageBinding binding;
  late WorkspaceId workspace;
  late PublicId id;
  final when = DateTime.utc(2026, 9, 29, 3);

  BudgetPlan plan(int version, String amount) => BudgetPlan(
    id: id,
    workspace: workspace,
    month: ReportMonth(2026, 9),
    limit: Money.parse(Currency('TWD', 2), amount),
    version: version,
  );

  setUp(() {
    work = root.createTempSync('case-');
    file = File('${work.path}/finance.db');
    workspace = WorkspaceId(PublicId.generate());
    id = PublicId.generate();
    binding = allocationBinding();
    db = ProbeDatabase(
      file,
      storageBinding: binding,
      correctionsAware: true,
      tombstonesAware: true,
      budgetsAware: true,
    );
  });
  tearDown(() async {
    await db.close();
    work.deleteSync(recursive: true);
  });

  test(
    'append, retry, update and tombstone retain full revision history',
    () async {
      final first = OperationId(PublicId.generate());
      final second = OperationId(PublicId.generate());
      final removal = OperationId(PublicId.generate());
      await appendBudgetRevision(db, plan(1, '100'), first, when);
      final retry = await appendBudgetRevision(
        db,
        plan(1, '100'),
        first,
        when.add(const Duration(days: 1)),
      );
      expect(retry.recordedAt, when);
      await appendBudgetRevision(db, plan(2, '120'), second, when);
      expect(
        (await currentBudgetPlans(db, workspace)).single.limit.majorText,
        '120.00',
      );
      await appendBudgetRevision(
        db,
        plan(3, '120'),
        removal,
        when,
        deleted: true,
      );
      expect(await currentBudgetPlans(db, workspace), isEmpty);
      final history = await budgetHistory(db, workspace);
      expect(history.map((r) => r.plan.version), [1, 2, 3]);
      expect(history.last.deleted, isTrue);
      await expectLater(
        appendBudgetRevision(
          db,
          plan(4, '120'),
          OperationId(PublicId.generate()),
          when,
        ),
        throwsFormatException,
      );
    },
  );

  test('operation conflict and stale or mutated deletion roll back', () async {
    final first = OperationId(PublicId.generate());
    await appendBudgetRevision(db, plan(1, '100'), first, when);
    for (final action in [
      () => appendBudgetRevision(db, plan(1, '101'), first, when),
      () => appendBudgetRevision(
        db,
        plan(3, '100'),
        OperationId(PublicId.generate()),
        when,
      ),
      () => appendBudgetRevision(
        db,
        plan(2, '101'),
        OperationId(PublicId.generate()),
        when,
        deleted: true,
      ),
    ]) {
      await expectLater(action(), throwsFormatException);
    }
    expect((await budgetHistory(db, workspace)).length, 1);
  });

  test(
    'reopen retains authority and malformed stored identity is rejected',
    () async {
      final operation = OperationId(PublicId.generate());
      await appendBudgetRevision(db, plan(1, '250'), operation, when);
      await db.close();
      db = ProbeDatabase(
        file,
        storageBinding: binding,
        correctionsAware: true,
        tombstonesAware: true,
        budgetsAware: true,
      );
      expect(
        (await currentBudgetPlans(db, workspace)).single.limit.majorText,
        '250.00',
      );
      await db.customStatement(
        'UPDATE budget_revisions SET payload=? WHERE workspace=?',
        ['{}', workspace.id.value],
      );
      await expectLater(budgetHistory(db, workspace), throwsFormatException);
    },
  );
}
