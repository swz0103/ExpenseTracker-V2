import 'dart:convert';
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
import 'package:validated_restore_probe/snapshot.dart';

void main() {
  final root = Directory('.dart_tool/budget-snapshot-tests')
    ..createSync(recursive: true);
  late Directory work;
  late StorageBinding sourceBinding;
  late ProbeDatabase source;
  late WorkspaceId workspace;
  final codec = SnapshotCodec(
    generationAware: true,
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: true,
  );

  ProbeDatabase database(
    File path,
    StorageBinding binding, {
    bool budgets = true,
  }) => ProbeDatabase(
    path,
    storageBinding: binding,
    correctionsAware: true,
    tombstonesAware: true,
    budgetsAware: budgets,
  );

  setUp(() {
    work = root.createTempSync('case-');
    sourceBinding = allocationBinding();
    source = database(File('${work.path}/source.db'), sourceBinding);
    workspace = WorkspaceId(PublicId.generate());
  });
  tearDown(() async {
    await source.close();
    work.deleteSync(recursive: true);
  });

  test(
    'budget revisions survive portable stage with regenerated local binding',
    () async {
      final id = PublicId.generate();
      BudgetPlan plan(int version, String limit) => BudgetPlan(
        id: id,
        workspace: workspace,
        month: ReportMonth(2026, 9),
        limit: Money.parse(Currency('TWD', 2), limit),
        version: version,
      );
      await appendBudgetRevision(
        source,
        plan(1, '100'),
        OperationId(PublicId.generate()),
        DateTime.utc(2026, 9, 29),
      );
      await appendBudgetRevision(
        source,
        plan(2, '120'),
        OperationId(PublicId.generate()),
        DateTime.utc(2026, 9, 30),
      );
      final captured = await codec.capture(source);
      final targetFile = File('${work.path}/target.db');
      final binding = allocationBinding();
      await codec.stage(
        captured,
        targetFile,
        openDatabase: (file) => database(file, binding),
      );
      final target = database(targetFile, binding);
      try {
        expect((await budgetHistory(target, workspace)).length, 2);
        expect(
          (await currentBudgetPlans(target, workspace)).single.limit.majorText,
          '120.00',
        );
        expect(await codec.capture(target), captured);
      } finally {
        await target.close();
      }
    },
  );

  test(
    'malformed budget authority is rejected before export or replacement',
    () async {
      await appendBudgetRevision(
        source,
        BudgetPlan(
          id: PublicId.generate(),
          workspace: workspace,
          month: ReportMonth(2026, 9),
          limit: Money.parse(Currency('TWD', 2), '100'),
        ),
        OperationId(PublicId.generate()),
        DateTime.utc(2026, 9, 29),
      );
      final captured = await codec.capture(source);
      final tampered =
          jsonDecode(utf8.decode(captured)) as Map<String, dynamic>;
      final table = tampered['tables'] as Map<String, dynamic>;
      (table['budget_revisions'] as List).single['payload'] = '{}';
      await expectLater(
        codec.stage(
          utf8.encode(jsonEncode(tampered)),
          File('${work.path}/tampered.db'),
          openDatabase: (file) => database(file, allocationBinding()),
        ),
        throwsA(isA<InvalidSnapshot>()),
      );
      await source.customStatement('UPDATE budget_revisions SET payload=?', [
        '{}',
      ]);
      await expectLater(codec.capture(source), throwsA(isA<InvalidSnapshot>()));
    },
  );

  test('schema 14 snapshot stages into schema 15 with empty budgets', () async {
    await source.close();
    source = database(
      File('${work.path}/old.db'),
      sourceBinding,
      budgets: false,
    );
    final old = SnapshotCodec(
      generationAware: true,
      correctionsAware: true,
      tombstonesAware: true,
    );
    final bytes = await old.capture(source);
    final targetFile = File('${work.path}/upgraded.db');
    final binding = allocationBinding();
    await codec.stage(
      bytes,
      targetFile,
      openDatabase: (file) => database(file, binding),
    );
    final target = database(targetFile, binding);
    try {
      expect(await budgetHistory(target, workspace), isEmpty);
      expect(target.schemaVersion, 15);
    } finally {
      await target.close();
    }
  });
}
