import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';

import '../test/support.dart' show MemoryVault, engineAt, setup, password, ref;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

bool equalBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> capacity(Future<void> Function() work) async {
  try {
    await work();
  } on PreviewCapacity {
    return;
  }
  throw StateError('Capacity guard did not reject');
}

Future<int> timing(Future<void> Function() work) async {
  final watch = Stopwatch()..start();
  await work();
  return watch.elapsedMilliseconds;
}

/// Synthetic data only. No phone, network, user files or platform keys.
Future<void> main(List<String> args) async {
  if (args.isNotEmpty && (args.length != 1 || args.single != '--datasets=1')) {
    throw ArgumentError(
      'Use no arguments for ten datasets, or --datasets=1 for one capacity regression.',
    );
  }
  final datasetCount = args.isEmpty ? 10 : 1;
  final root = Directory('.dart_tool/scale-tests')..createSync(recursive: true);
  final report = <String, Object>{
    'startedUtc': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystemVersion,
    'dart': Platform.version,
    'processors': Platform.numberOfProcessors,
    'newTransactions': 0,
    'retries': 0,
    'datasets': <Object>[],
  };
  final total = Stopwatch()..start();
  final start = DateTime.utc(2006, 1, 1);
  final end = DateTime.utc(2026, 9, 27);
  final days = end.difference(start).inDays;
  for (var dataset = 0; dataset < datasetCount; dataset++) {
    final work = root.createTempSync('case-');
    final engine = engineAt(Directory('${work.path}/source'), MemoryVault());
    PreviewEngine? target;
    try {
      final recoveryKey = await setup(engine);
      final accounts = <Account>[];
      final oracle = <String, BigInt>{};
      final order = <({String id, String date})>[];
      final accountCount = dataset == 0 ? 1 : 32;
      var accepted = 0, retries = 0;
      Posting? last;
      final writes = Stopwatch()..start();
      for (var i = 0; i < accountCount; i++) {
        final currency = [
          Currency('TWD', 2),
          Currency('USD', 2),
          Currency('JPY', 0),
        ][i % 3];
        final account = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: List.filled(100, '帳').join(),
          kind: i.isEven ? AccountKind.cash : AccountKind.bank,
          currency: currency,
          openedOn: BusinessDate(2006, 1, 1),
        );
        final units = i.isEven ? 100000 : -100000;
        final opening = Posting.opening(
          id: PublicId.generate(),
          operation: OperationKey(
            engine.workspace,
            OperationId(PublicId.generate()),
          ),
          date: account.openedOn,
          account: ref(account),
          amount: Money(currency, BigInt.from(units)),
        );
        await engine.createAccount(account, opening);
        accepted++;
        await engine.createAccount(account, opening);
        retries++;
        accounts.add(account);
        oracle[account.id.value] = BigInt.from(units);
        order.add((id: opening.id.value, date: opening.date.toString()));
      }
      if (accountCount == 32) {
        final extra = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: '超限',
          kind: AccountKind.cash,
          currency: Currency('TWD', 2),
          openedOn: BusinessDate(2006, 1, 1),
        );
        final opening = Posting.opening(
          id: PublicId.generate(),
          operation: OperationKey(
            engine.workspace,
            OperationId(PublicId.generate()),
          ),
          date: extra.openedOn,
          account: ref(extra),
          amount: Money(extra.currency, BigInt.zero),
        );
        await capacity(() => engine.createAccount(extra, opening));
      }
      final checkpoints = <Object>[];
      for (var i = accountCount; i < LedgerSession.maxEvents; i++) {
        final a = accounts[(i * 17) % accounts.length];
        final units = 1 + (i * 7919 + dataset * 104729) % 100000;
        final income = i % 3 == 0;
        final instant = i == LedgerSession.maxEvents - 1
            ? end
            : start.add(Duration(days: (i * 3559) % (days + 1)));
        final date = BusinessDate(instant.year, instant.month, instant.day);
        final factory = income ? Posting.income : Posting.expense;
        final posting = factory(
          id: PublicId.generate(),
          operation: OperationKey(
            engine.workspace,
            OperationId(PublicId.generate()),
          ),
          date: date,
          account: ref(a),
          amount: Money(a.currency, BigInt.from(units)),
        );
        await engine.post(posting);
        accepted++;
        await engine.post(posting);
        retries++;
        oracle[a.id.value] =
            oracle[a.id.value]! + BigInt.from(income ? units : -units);
        order.add((id: posting.id.value, date: date.toString()));
        last = posting;
        if ((i + 1) % 1000 == 0) {
          final summaryMs = await timing(() async {
            final summaries = await engine.accounts();
            for (final s in summaries) {
              check(
                s.balance.minorUnits == oracle[s.account.id.value],
                'Independent balance mismatch',
              );
            }
          });
          final pageMs = await timing(() async {
            check((await engine.entries()).length == 30, 'First page size');
          });
          checkpoints.add({
            'events': i + 1,
            'elapsedMs': writes.elapsedMilliseconds,
            'summaryMs': summaryMs,
            'firstPageMs': pageMs,
          });
          stdout.writeln(
            'dataset ${dataset + 1}/$datasetCount: ${i + 1} committed, $retries replays',
          );
        }
      }
      final writeMs = writes.elapsedMilliseconds;
      final a = accounts.first;
      final overflow = Posting.income(
        id: PublicId.generate(),
        operation: OperationKey(
          engine.workspace,
          OperationId(PublicId.generate()),
        ),
        date: BusinessDate(2026, 9, 27),
        account: ref(a),
        amount: Money(a.currency, BigInt.one),
      );
      await capacity(() => engine.post(overflow));
      // Pagination oracle is independently sorted from accepted command inputs.
      order.sort((a, b) {
        final date = b.date.compareTo(a.date);
        return date != 0 ? date : b.id.compareTo(a.id);
      });
      var offset = 0;
      LedgerEntry? cursor;
      final pagingMs = await timing(() async {
        while (true) {
          final page = await engine.entries(before: cursor);
          if (page.isEmpty) break;
          for (final entry in page) {
            check(
              entry.id.value == order[offset++].id,
              'Pagination oracle mismatch',
            );
          }
          cursor = page.last;
        }
        check(offset == accepted, 'Pagination count mismatch');
      });
      late String backup;
      stdout.writeln(
        'dataset ${dataset + 1}: all pages verified; creating encrypted backup',
      );
      final backupMs = await timing(() async {
        backup = await engine.exportBackup();
      });
      final plain = await EnvelopeCodec().openWithRecovery(backup, recoveryKey);
      final tables = (jsonDecode(utf8.decode(plain)) as Map)['tables'] as Map;
      check(
        (tables['events'] as List).length == accepted,
        'Transaction count mismatch',
      );
      check(
        (tables['receipts'] as List).length == accepted,
        'Receipt count mismatch',
      );
      check(
        (tables['audit'] as List).length == accepted,
        'Audit count mismatch',
      );
      final rows = tables.values.fold<int>(
        0,
        (sum, value) => sum + (value as List).length,
      );
      stdout.writeln(
        'dataset ${dataset + 1}: backup ${plain.length} bytes verified; restoring into clean ledger',
      );
      check(
        plain.length < EnvelopeCodec.maxPayloadBytes && rows < 50000,
        'Capacity does not fit backup',
      );
      await engine.lock();
      target = engineAt(Directory('${work.path}/restored'), MemoryVault());
      await setup(target);
      final recovery = dataset.isOdd;
      final restoreMs = await timing(
        () => target!.importBackup(
          backup,
          recovery ? recoveryKey : password,
          recovery: recovery,
        ),
      );
      final restored = await EnvelopeCodec().openWithPassword(
        await target.exportBackup(),
        password,
      );
      check(equalBytes(plain, restored), 'Full restored content differs');
      await target.post(
        last!,
      ); // Idempotency remains possible at capacity after import.
      for (final summary in await target.accounts()) {
        check(
          summary.balance.minorUnits == oracle[summary.account.id.value],
          'Restored balance mismatch',
        );
      }
      await capacity(() => target!.post(overflow));
      await target.lock();
      final reopenMs = await timing(() => target!.unlock(password));
      check((await target.entries()).length == 30, 'Reopen failed');
      (report['datasets'] as List).add({
        'dataset': dataset + 1,
        'accounts': accountCount,
        'newTransactions': accepted,
        'retriesDuringWrites': retries,
        'extraRetryAfterRestore': 1,
        'dateRange': ['2006-01-01', '2026-09-27'],
        'writeAndRetryMs': writeMs,
        'checkpoints': checkpoints,
        'allPagesMs': pagingMs,
        'backupMs': backupMs,
        'restoreMs': restoreMs,
        'reopenMs': reopenMs,
        'restoreCredential': recovery ? 'recovery' : 'password',
        'payloadBytes': plain.length,
        'envelopeBytes': utf8.encode(backup).length,
        'authorityRows': rows,
      });
      report['newTransactions'] = (report['newTransactions'] as int) + accepted;
      report['retries'] = (report['retries'] as int) + retries + 1;
      stdout.writeln(
        'dataset ${dataset + 1} verified: ${plain.length} payload bytes, restore ${restoreMs}ms',
      );
    } finally {
      await engine.lock();
      await target?.lock();
    }
    check(
      work.absolute.path.startsWith(
        '${root.absolute.path}${Platform.pathSeparator}',
      ),
      'Unsafe cleanup',
    );
    work.deleteSync(recursive: true);
  }
  report['elapsedMs'] = total.elapsedMilliseconds;
  report['status'] = 'passed';
  File(
    args.isEmpty
        ? '.dart_tool/scale-report.json'
        : '.dart_tool/scale-report-single.json',
  ).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
  stdout.writeln(
    'PASS: ${report['newTransactions']} distinct transactions, ${report['retries']} retries, ${total.elapsed}',
  );
}
