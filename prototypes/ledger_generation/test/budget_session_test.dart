import 'dart:io';

import 'package:budgets/budgets.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:reports/reports.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('.dart_tool/budget-session-tests')
    ..createSync(recursive: true);
  late Directory work;
  late FixtureKeySlots keys;
  late WorkspaceId workspace;
  const password = 'synthetic-budget-backup-only';

  LedgerStore store(String name, FixtureKeySlots slots) => LedgerStore(
    Directory('${work.path}/$name'),
    slots,
    catalogProtection: fixtureCatalogProtection(slots),
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
  );
  OperationId operation() => OperationId(PublicId.generate());

  setUp(() {
    work = root.createTempSync('case-');
    keys = FixtureKeySlots(Directory('${work.path}/keys'));
    workspace = WorkspaceId(PublicId.generate());
  });
  tearDown(() {
    final base = root.resolveSymbolicLinksSync();
    final target = work.resolveSymbolicLinksSync();
    if (!target.startsWith('$base${Platform.pathSeparator}')) {
      throw StateError('Unsafe cleanup');
    }
    work.deleteSync(recursive: true);
  });

  test(
    'encrypted budget revisions survive both independent clean restores',
    () async {
      final active = store('active', keys);
      await active.initialize(operation());
      final id = PublicId.generate();
      BudgetPlan plan(int version, String limit) => BudgetPlan(
        id: id,
        workspace: workspace,
        month: ReportMonth(2026, 9),
        limit: Money.parse(Currency('TWD', 2), limit),
        version: version,
      );
      final firstOperation = operation();
      await active.withSession((session) async {
        await session.saveBudget(
          plan(1, '100'),
          firstOperation,
          DateTime.utc(2026, 9, 29),
        );
        await session.saveBudget(
          plan(1, '100'),
          firstOperation,
          DateTime.utc(2026, 9, 29),
        );
        await session.saveBudget(
          plan(2, '120'),
          operation(),
          DateTime.utc(2026, 9, 30),
        );
        expect(
          (await session.budgets(workspace)).single.limit.majorText,
          '120.00',
        );
        expect(await session.budgetRevisions(workspace), hasLength(2));
      });
      final before = await active.snapshot();
      final backup = await active.backup(password);
      for (final method in ['password', 'recovery']) {
        final slots = FixtureKeySlots(Directory('${work.path}/$method-keys'));
        final restored = store(method, slots);
        await restored.restore(
          backup.envelope,
          operation(),
          password: method == 'password' ? password : null,
          recoveryKey: method == 'recovery' ? backup.recoveryKey : null,
        );
        expect(await restored.snapshot(), before);
        await restored.withSession((session) async {
          expect(await session.budgetRevisions(workspace), hasLength(2));
          expect((await session.budgets(workspace)).single.version, 2);
          await expectLater(
            session.saveBudget(
              plan(2, '999'),
              firstOperation,
              DateTime.utc(2026),
            ),
            throwsFormatException,
          );
        });
        expect(await restored.snapshot(), before);
      }
    },
  );

  test(
    'schema 14 encrypted backup opens in schema 15 with no invented budgets',
    () async {
      final oldSlots = FixtureKeySlots(Directory('${work.path}/old-keys'));
      final old = LedgerStore(
        Directory('${work.path}/old'),
        oldSlots,
        catalogProtection: fixtureCatalogProtection(oldSlots),
        correctionsAware: true,
        tombstonesAware: true,
      );
      await old.initialize(operation());
      final backup = await old.backup(password);
      final upgraded = store('upgraded', keys);
      await upgraded.restore(backup.envelope, operation(), password: password);
      await upgraded.withSession((session) async {
        expect(await session.budgets(workspace), isEmpty);
        expect(await session.budgetRevisions(workspace), isEmpty);
      });
      expect(await upgraded.snapshot(), isNotEmpty);
    },
  );
}
