import 'dart:convert';
import 'dart:io';

import 'package:expense_preview/preview_engine.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

import '../test/support.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
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
      schemaVersion: 13,
      draftCheckpoint: (p) {
        if (p == point) exit(73);
      },
    );
    await engine.unlock(password);
    if (point == 'draft-staged' || point == 'draft-published') {
      final fields = (await engine.entryDraft())!.fields;
      await engine.saveEntryDraft(
        EntryFields(
          income: fields.income,
          amount: fields.amount,
          date: fields.date,
          accountId: fields.accountId,
          correctionOf: fields.correctionOf,
          correctionReason: 'published reason',
        ),
      );
    } else {
      await engine.submitEntryDraft();
    }
    throw StateError('Checkpoint not reached');
  }

  final root = Directory('.dart_tool/correction-draft-process-tests')
    ..createSync(recursive: true);
  final watch = Stopwatch()..start();
  final cases = <Map<String, Object>>[];
  for (final point in [
    'draft-staged',
    'draft-published',
    'draft-prepared',
    'draft-committed',
  ]) {
    final work = root.createTempSync('case-');
    final vault = MemoryVault();
    final app = Directory('${work.path}/app');
    var engine = engineAt(app, vault, schemaVersion: 13);
    try {
      await setup(engine);
      final accountRow = account(engine);
      await engine.createAccount(accountRow, opening(accountRow));
      final original = Posting.expense(
        id: PublicId.generate(),
        operation: OperationKey(
          engine.workspace,
          OperationId(PublicId.generate()),
        ),
        date: BusinessDate(2026, 9, 28),
        account: ref(accountRow),
        amount: Money.parse(accountRow.currency, '10'),
      );
      await engine.post(original);
      final draft = await engine.saveEntryDraft(
        EntryFields(
          income: false,
          amount: '7',
          date: '2026-10-01',
          accountId: accountRow.id,
          correctionOf: original.id,
          correctionReason: 'initial reason',
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
      engine = engineAt(app, vault, schemaVersion: 13);
      await engine.unlock(password);
      final current = await engine.entryDraft();
      if (point == 'draft-committed') {
        check(current == null, 'committed pair reconciles');
      } else {
        check(current?.id == draft.id, 'draft identity retained');
        check(
          current!.fields.correctionReason ==
              (point == 'draft-published'
                  ? 'published reason'
                  : 'initial reason'),
          'atomic draft publication',
        );
        check((await engine.entries()).length == 2, 'no partial pair');
        check(
          (await engine.accounts()).single.balance.minorUnits.toInt() == 9000,
          'pre-commit balance',
        );
        await engine.submitEntryDraft();
      }
      check((await engine.entries()).length == 4, 'exactly four events');
      check(
        (await engine.accounts()).single.balance.minorUnits.toInt() == 9300,
        'exact replacement balance',
      );
      check(await engine.entryDraft() == null, 'draft consumed');
      final history = await engine.activity(original.id);
      check(history.length == 3, 'full correction activity');
      check(
        history.any((row) => row.entry.id == draft.id),
        'replacement linked to original',
      );
      final backup = await engine.exportBackup();
      check(backup.isNotEmpty, 'backup after reconciliation');
      cases.add({
        'checkpoint': point,
        'childExit': child.exitCode,
        'events': 4,
        'balanceMinor': 9300,
        'activity': 3,
        'status': 'passed',
      });
    } finally {
      await engine.lock();
      deleteSynthetic(work, root);
    }
  }
  final report = {
    'status': 'passed',
    'cases': cases,
    'elapsedMs': watch.elapsedMilliseconds,
  };
  await File('.dart_tool/correction-draft-process-report.json')
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  stdout.writeln(jsonEncode(report));
}
