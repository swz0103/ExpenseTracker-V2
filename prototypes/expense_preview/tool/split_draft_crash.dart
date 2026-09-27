import 'dart:convert';
import 'dart:io';

import 'package:categories/categories.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:foundation_values/foundation_values.dart';

import '../test/support.dart';

void check(bool condition, String name) {
  if (!condition) throw StateError(name);
}

Future<void> main(List<String> args) async {
  if ([
    'dart',
    'dart.exe',
    'dartvm.exe',
  ].contains(File(Platform.resolvedExecutable).uri.pathSegments.last)) {
    throw StateError('Build the CLI bundle before running process tests.');
  }
  if (args.isNotEmpty) {
    final work = Directory(args[0]), point = args[1];
    final vault = MemoryVault()
      ..values.addAll(
        Map<String, String>.from(
          jsonDecode(
            await File('${work.path}/vault.synthetic.json').readAsString(),
          ) as Map,
        ),
      );
    final engine = engineAt(
      Directory('${work.path}/app'),
      vault,
      schemaVersion: 9,
      draftCheckpoint: (p) {
        if (p == point) exit(73);
      },
    );
    await engine.unlock(password);
    if (point == 'draft-staged' || point == 'draft-published') {
      final d = (await engine.entryDraft())!;
      await engine.saveEntryDraft(
        EntryFields(
          income: false,
          split: true,
          amount: '12',
          date: d.fields.date,
          accountId: d.fields.accountId,
          splits: [
            SplitFields(
              categoryId: d.fields.splits[0].categoryId,
              amount: '4.25',
            ),
            SplitFields(
              categoryId: d.fields.splits[1].categoryId,
              amount: '7.75',
            ),
          ],
        ),
      );
    } else {
      await engine.submitEntryDraft();
    }
    throw StateError('Checkpoint not reached');
  }
  final root = Directory('.dart_tool/split-draft-process-tests')
    ..createSync(recursive: true);
  final report = <String, Object>{
    'startedUtc': DateTime.now().toUtc().toIso8601String(),
    'cases': <Object>[],
  };
  final watch = Stopwatch()..start();
  for (final point in [
    'draft-staged',
    'draft-published',
    'draft-prepared',
    'draft-committed',
  ]) {
    final work = root.createTempSync('case-'),
        vault = MemoryVault(),
        app = Directory('${work.path}/app');
    var engine = engineAt(app, vault, schemaVersion: 9);
    try {
      await setup(engine);
      final a = account(engine);
      await engine.createAccount(a, opening(a));
      final cats = [PublicId.generate(), PublicId.generate()];
      for (var i = 0; i < 2; i++) {
        await engine.createCategory(
          OperationKey(engine.workspace, OperationId(PublicId.generate())),
          cats[i],
          'Split $i',
          CategoryKind.expense,
        );
      }
      final d = await engine.saveEntryDraft(
        EntryFields(
          income: false,
          split: true,
          amount: '10',
          date: '2026-09-28',
          accountId: a.id,
          splits: [
            SplitFields(categoryId: cats[0], amount: '3.25'),
            SplitFields(categoryId: cats[1], amount: '6.75'),
          ],
        ),
      );
      await engine.lock();
      await File('${work.path}/vault.synthetic.json')
          .writeAsString(jsonEncode(vault.values), flush: true);
      final child = await Process.run(Platform.resolvedExecutable, [
        work.absolute.path,
        point,
      ]);
      check(
        child.exitCode == 73,
        'Expected exit 73 at $point: ${child.exitCode} ${child.stderr}',
      );
      engine = engineAt(app, vault, schemaVersion: 9);
      await engine.unlock(password);
      final current = await engine.entryDraft();
      if (point == 'draft-committed') {
        check(current == null, 'committed slot reconciles');
      } else {
        check(current?.id == d.id, 'identity retained');
        check(
          current!.fields.amount == (point == 'draft-published' ? '12' : '10'),
          'atomic publication',
        );
        check(
          (await engine.entries()).length == 1,
          'no uncommitted financial effect',
        );
        await engine.submitEntryDraft();
      }
      final expected = point == 'draft-published' ? 8800 : 9000;
      final rows = await engine.allocations(d.id);
      check(
        rows
                .singleWhere((r) => r.categoryId == cats[0])
                .amount
                .minorUnits
                .toInt() ==
            (point == 'draft-published' ? 425 : 325),
        'first allocation',
      );
      check(
        rows
                .singleWhere((r) => r.categoryId == cats[1])
                .amount
                .minorUnits
                .toInt() ==
            (point == 'draft-published' ? 775 : 675),
        'second allocation',
      );
      check(
        (await engine.accounts()).single.balance.minorUnits.toInt() == expected,
        'independent balance',
      );
      check((await engine.entries()).length == 2, 'exactly once');
      check(await engine.entryDraft() == null, 'slot consumed');
      (report['cases'] as List).add({
        'checkpoint': point,
        'childExit': child.exitCode,
        'events': 2,
        'balanceMinor': expected,
        'status': 'passed',
      });
    } finally {
      await engine.lock();
      deleteSynthetic(work, root);
    }
  }
  report.addAll({'status': 'passed', 'elapsedMs': watch.elapsedMilliseconds});
  await File('.dart_tool/split-draft-process-report.json')
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  stdout.writeln(jsonEncode(report));
}
