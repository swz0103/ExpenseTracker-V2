import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:budgets/budgets.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:reports/reports.dart';
import 'package:storage_generation_probe/generation_store.dart';

import 'support.dart';

void main() {
  final root = Directory('.dart_tool/budget-upgrade-tests')
    ..createSync(recursive: true);
  late Directory work;
  late MemoryVault vault;
  late PreviewEngine engine;

  setUp(() {
    work = root.createTempSync('case-');
    vault = MemoryVault();
    engine = engineAt(work, vault, schemaVersion: 14);
  });
  tearDown(() async {
    await engine.lock();
    deleteSynthetic(work, root);
  });

  test(
    'interrupted 14 to 15 upgrade retains source and resumes with dual restore',
    () async {
      final sourceRecovery = await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      await engine.post(
        Posting.expense(
          id: PublicId.generate(),
          operation: OperationKey(
            engine.workspace,
            OperationId(PublicId.generate()),
          ),
          date: BusinessDate(2026, 9, 29),
          account: ref(a),
          amount: Money.parse(a.currency, '10'),
        ),
      );
      final workspace = engine.workspace;
      final priorBalance = (await engine.accounts()).single.balance;
      await engine.lock();

      engine = engineAt(
        work,
        vault,
        schemaVersion: 15,
        checkpoint: (point) {
          if (point == '14:table:budget_revisions') {
            throw StateError('injected');
          }
        },
      );
      await expectLater(
        engine.unlock(password),
        throwsA(isA<PreviewUpgradeRequired>()),
      );
      await expectLater(
        engine.upgrade(password),
        throwsA(isA<GenerationUnavailable>()),
      );
      await engine.lock();
      engine = engineAt(work, vault, schemaVersion: 14);
      await engine.unlock(password);
      expect((await engine.accounts()).single.balance, priorBalance);
      expect(await engine.exportBackup(), isNotEmpty);
      await engine.lock();

      engine = engineAt(work, vault, schemaVersion: 15);
      await engine.upgrade(password);
      expect(engine.capabilities.budgets, isTrue);
      expect((await engine.accounts()).single.balance, priorBalance);
      expect(await engine.savedBudgets(), isEmpty);
      final plan = BudgetPlan(
        id: PublicId.generate(),
        workspace: workspace,
        month: ReportMonth(2026, 9),
        limit: Money.parse(a.currency, '100'),
      );
      final savedOperation = OperationId(PublicId.generate());
      await engine.saveBudget(plan, savedOperation);
      await engine.saveBudget(plan, savedOperation);
      expect(await engine.savedBudgets(), hasLength(1));
      expect(
        (await engine.evaluateMonthlyBudget(plan)).spent.majorText,
        '10.00',
      );
      final backup = await engine.exportBackup();

      final files = Directory('${work.path}/upgrade-backups')
          .listSync()
          .whereType<File>()
          .toList();
      expect(files, hasLength(greaterThanOrEqualTo(1)));
      final oldEnvelope = await files.last.readAsString();
      final oldPlain = await EnvelopeCodec().openWithPassword(
        oldEnvelope,
        password,
      );
      expect(jsonDecode(utf8.decode(oldPlain))['schema'], 14);
      expect(
        await EnvelopeCodec().openWithRecovery(oldEnvelope, sourceRecovery),
        oldPlain,
      );

      for (final recovery in [false, true]) {
        final targetDir = root.createTempSync('restore-');
        final target = engineAt(targetDir, MemoryVault(), schemaVersion: 15);
        try {
          await setup(target);
          await target.importBackup(
            backup,
            recovery ? sourceRecovery : password,
            recovery: recovery,
          );
          expect((await target.accounts()).single.balance, priorBalance);
          expect((await target.savedBudgets()).single.id, plan.id);
        } finally {
          await target.lock();
          deleteSynthetic(targetDir, root);
        }
      }
    },
  );
}
