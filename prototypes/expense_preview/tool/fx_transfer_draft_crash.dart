import 'package:accounts/accounts.dart';
import 'package:foundation_values/foundation_values.dart';

import 'dart:convert';
import 'dart:io';

import 'package:expense_preview/preview_engine.dart';

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
    throw StateError(
      'Build and run the CLI bundle first; nested dart run replaces a loaded native DLL.',
    );
  }
  if (args.isNotEmpty) {
    final work = Directory(args[0]);
    final point = args[1];
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
      final prior = (await engine.entryDraft())!;
      await engine.saveEntryDraft(
        EntryFields(
          income: false,
          transfer: true,
          destinationId: prior.fields.destinationId,
          fee: prior.fields.fee,
          amount: '9',
          received: '43',
          date: prior.fields.date,
          accountId: prior.fields.accountId,
        ),
      );
    } else {
      await engine.submitEntryDraft();
    }
    throw StateError('Crash checkpoint was not reached');
  }
  final root = Directory('.dart_tool/fx-transfer-draft-process-tests')
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
    final work = root.createTempSync('case-');
    final vault = MemoryVault();
    final app = Directory('${work.path}/app');
    var engine = engineAt(app, vault, schemaVersion: 9);
    try {
      await setup(engine);
      final a = account(engine),
          b = Account.open(
            id: PublicId.generate(),
            workspace: engine.workspace,
            name: 'JPY',
            kind: AccountKind.bank,
            currency: Currency('JPY', 0),
            openedOn: a.openedOn,
          );
      await engine.createAccount(a, opening(a));
      await engine.createAccount(b, opening(b));
      final draft = await engine.saveEntryDraft(
        EntryFields(
          income: false,
          transfer: true,
          destinationId: b.id,
          fee: '1.25',
          amount: '7',
          received: '31',
          date: '2026-09-27',
          accountId: a.id,
        ),
      );
      await engine.lock();
      // Synthetic test credentials only; ignored temporary directory, never upload.
      await File('${work.path}/vault.synthetic.json')
          .writeAsString(jsonEncode(vault.values), flush: true);
      final child = await Process.run(Platform.resolvedExecutable, [
        work.absolute.path,
        point,
      ]);
      check(
        child.exitCode == 73,
        'Expected real process exit at $point; received ${child.exitCode}; ${child.stderr}',
      );
      engine = engineAt(app, vault, schemaVersion: 9);
      await engine.unlock(password);
      final current = await engine.entryDraft();
      if (point == 'draft-committed') {
        check(current == null, 'committed draft must reconcile');
      } else {
        check(current?.id == draft.id, 'stable identity after exit');
        check(
          current!.fields.amount == (point == 'draft-published' ? '9' : '7'),
          'atomic publication',
        );
        check(
          (await engine.entries()).length == 2,
          'uncommitted has no financial effect',
        );
        await engine.submitEntryDraft();
      }
      check((await engine.entries()).length == 3, 'one financial effect');
      check((await engine.entries()).first.id == draft.id, 'same event ID');
      final expected = point == 'draft-published' ? 8975 : 9175;
      final targetExpected = point == 'draft-published' ? 143 : 131;
      check(
        (await engine.accounts())
                .singleWhere((r) => r.account.id == a.id)
                .balance
                .minorUnits
                .toString() ==
            '$expected',
        'balance',
      );
      check(
        (await engine.accounts())
                .singleWhere((r) => r.account.id == b.id)
                .balance
                .minorUnits
                .toInt() ==
            targetExpected,
        'destination balance',
      );
      check(await engine.entryDraft() == null, 'completion consumes slot');
      (report['cases'] as List).add({
        'checkpoint': point,
        'childExit': child.exitCode,
        'events': 3,
        'destinationMinor': targetExpected,
        'balanceMinor': expected,
        'status': 'passed',
      });
    } finally {
      await engine.lock();
      final resolved = work.resolveSymbolicLinksSync();
      if (!resolved.startsWith(
        root.resolveSymbolicLinksSync() + Platform.pathSeparator,
      )) {
        throw StateError('Unsafe test cleanup');
      }
      work.deleteSync(recursive: true);
    }
  }
  report['elapsedMs'] = watch.elapsedMilliseconds;
  report['status'] = 'passed';
  await File('.dart_tool/fx-transfer-draft-process-report.json')
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  stdout.writeln(jsonEncode(report));
}
