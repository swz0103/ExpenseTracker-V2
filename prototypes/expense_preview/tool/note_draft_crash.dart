import 'dart:convert';
import 'dart:io';

import 'package:categories/categories.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

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
      schemaVersion: 12,
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
          noteOf: d.fields.noteOf,
          noteRevision: d.fields.noteRevision,
          amount: '',
          date: '',
          noteText: 'after',
        ),
      );
    } else {
      await engine.submitEntryDraft();
    }
    throw StateError('Checkpoint not reached');
  }
  final root = Directory('.dart_tool/note-draft-process-tests')
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
    var engine = engineAt(app, vault, schemaVersion: 12);
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
      final original = Posting.expense(
        id: PublicId.generate(),
        operation: OperationKey(
          engine.workspace,
          OperationId(PublicId.generate()),
        ),
        date: BusinessDate(2026, 9, 27),
        account: ref(a),
        amount: Money.parse(a.currency, '20'),
        allocations: [
          for (final cat in cats)
            Allocation(
              cat,
              Money.parse(a.currency, '10'),
              expectedCategoryVersion: 1,
            ),
        ],
      );
      await engine.post(original);
      final d = await engine.saveEntryDraft(
        EntryFields(
          income: false,
          noteOf: original.id,
          amount: '',
          date: '',
          noteText: 'before',
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
      engine = engineAt(app, vault, schemaVersion: 12);
      await engine.unlock(password);
      final current = await engine.entryDraft();
      if (point == 'draft-committed') {
        check(current == null, 'committed slot reconciles');
      } else {
        check(current?.id == d.id, 'identity retained');
        check(
          current!.fields.noteText ==
              (point == 'draft-published' ? 'after' : 'before'),
          'atomic publication',
        );
        check(
          (await engine.entries()).length == 2,
          'no uncommitted financial effect',
        );
        await engine.submitEntryDraft();
      }
      final expected = 8000;
      check(
        (await engine.entryNote(original.id)).revision == 1,
        'exactly one revision',
      );
      check(
        (await engine.entryNote(original.id)).text ==
            (point == 'draft-published' ? 'after' : 'before'),
        'exact note',
      );
      check(
        (await engine.accounts()).single.balance.minorUnits.toInt() == expected,
        'unchanged balance',
      );
      check((await engine.entries()).length == 2, 'no financial event');
      check(await engine.entryDraft() == null, 'slot consumed');
      (report['cases'] as List).add({
        'checkpoint': point,
        'childExit': child.exitCode,
        'events': 2,
        'noteRevisions': 1,
        'balanceMinor': expected,
        'status': 'passed',
      });
    } finally {
      await engine.lock();
      deleteSynthetic(work, root);
    }
  }
  report.addAll({'status': 'passed', 'elapsedMs': watch.elapsedMilliseconds});
  await File('.dart_tool/note-draft-process-report.json')
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  stdout.writeln(jsonEncode(report));
}
