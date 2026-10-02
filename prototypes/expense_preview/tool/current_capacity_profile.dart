import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:reports/reports.dart';

import '../test/support.dart'
    show MemoryVault, deleteSynthetic, engineAt, password, ref, setup;

Future<int> _timed(Future<void> Function() operation) async {
  final watch = Stopwatch()..start();
  await operation();
  return watch.elapsedMilliseconds;
}

int _directoryBytes(Directory directory) => directory
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .fold(0, (total, file) => total + file.lengthSync());

Future<int> _allPages(PreviewEngine engine) async {
  var count = 0;
  LedgerEntry? cursor;
  while (true) {
    final page = await engine.entries(before: cursor);
    if (page.isEmpty) return count;
    count += page.length;
    cursor = page.last;
  }
}

/// Current-schema host profile only. It is not an Android latency claim and
/// never reads user data, platform credentials, or the network.
Future<void> main() async {
  const checkpoints = [100, 1000, 5000];
  final root = Directory('.dart_tool/current-capacity-profile')
    ..createSync(recursive: true);
  final work = root.createTempSync('case-');
  final sourceDirectory = Directory('${work.path}/source');
  final engine = engineAt(
    sourceDirectory,
    MemoryVault(),
    schemaVersion: currentPreviewSchemaVersion,
  );
  final report = <String, Object?>{
    'startedUtc': DateTime.now().toUtc().toIso8601String(),
    'scope': 'current-schema-host-profile',
    'schema': currentPreviewSchemaVersion,
    'platform': Platform.operatingSystemVersion,
    'dart': Platform.version,
    'processors': Platform.numberOfProcessors,
    'checkpoints': <Object>[],
  };
  final total = Stopwatch()..start();
  try {
    late String recoveryKey;
    report['setupMs'] = await _timed(() async {
      recoveryKey = await setup(engine);
    });
    final currency = Currency('TWD', 2);
    final account = Account.open(
      id: PublicId.generate(),
      workspace: engine.workspace,
      name: '容量基準帳戶',
      kind: AccountKind.bank,
      currency: currency,
      openedOn: BusinessDate(2024, 1, 1),
    );
    final opening = Posting.opening(
      id: PublicId.generate(),
      operation: OperationKey(
        engine.workspace,
        OperationId(PublicId.generate()),
      ),
      date: account.openedOn,
      account: ref(account),
      amount: Money(currency, BigInt.from(100000000)),
    );
    await engine.createAccount(account, opening);
    var events = 1;
    var lastCheckpointElapsed = 0;
    final writes = Stopwatch()..start();
    for (var next = 2; next <= checkpoints.last; next++) {
      final day = 1 + next % 28;
      final posting = (next.isEven ? Posting.expense : Posting.income)(
        id: PublicId.generate(),
        operation: OperationKey(
          engine.workspace,
          OperationId(PublicId.generate()),
        ),
        date: BusinessDate(2026, 9, day),
        account: ref(account),
        amount: Money(currency, BigInt.from(1 + next % 100000)),
      );
      await engine.post(posting);
      events++;
      if (events % 500 == 0) {
        stdout.writeln(
          'current schema $currentPreviewSchemaVersion: $events/${checkpoints.last} events',
        );
      }
      if (!checkpoints.contains(events)) continue;

      final cumulativeWriteMs = writes.elapsedMilliseconds;
      final firstPageMs = await _timed(() async {
        if ((await engine.entries()).length != 30) {
          throw StateError('Unexpected first page size');
        }
      });
      final accountSummaryMs = await _timed(() async {
        if ((await engine.accounts()).length != 1) {
          throw StateError('Unexpected account count');
        }
      });
      final monthlyReportMs = await _timed(() async {
        await engine.monthlyReport(ReportMonth(2026, 9));
      });
      var pagedEvents = 0;
      final allPagesMs = await _timed(() async {
        pagedEvents = await _allPages(engine);
      });
      if (pagedEvents != events) throw StateError('Pagination count mismatch');

      late String envelope;
      final backupMs = await _timed(() async {
        envelope = await engine.exportBackup();
      });
      final plain = await EnvelopeCodec().openWithRecovery(
        envelope,
        recoveryKey,
      );
      final snapshot = jsonDecode(utf8.decode(plain)) as Map;
      final tables = snapshot['tables'] as Map;
      final authorityRows = tables.values.fold<int>(
        0,
        (total, rows) => total + (rows as List).length,
      );

      final restoredDirectory = Directory('${work.path}/restored-$events');
      final restored = engineAt(
        restoredDirectory,
        MemoryVault(),
        schemaVersion: currentPreviewSchemaVersion,
      );
      late int restoreMs;
      late int reopenMs;
      try {
        await setup(restored);
        restoreMs = await _timed(
          () => restored.importBackup(envelope, password, recovery: false),
        );
        await restored.lock();
        reopenMs = await _timed(() => restored.unlock(password));
        if ((await _allPages(restored)) != events) {
          throw StateError('Restored pagination count mismatch');
        }
      } finally {
        await restored.lock();
      }
      final row = <String, Object?>{
        'events': events,
        'windowWriteMs': cumulativeWriteMs - lastCheckpointElapsed,
        'cumulativeWriteMs': cumulativeWriteMs,
        'firstPageMs': firstPageMs,
        'accountSummaryMs': accountSummaryMs,
        'monthlyReportMs': monthlyReportMs,
        'allPagesMs': allPagesMs,
        'backupMs': backupMs,
        'restoreMs': restoreMs,
        'reopenMs': reopenMs,
        'payloadBytes': plain.length,
        'envelopeBytes': utf8.encode(envelope).length,
        'authorityRows': authorityRows,
        'sourceFilesBytes': _directoryBytes(sourceDirectory),
        'residentBytesAfterCheckpoint': ProcessInfo.currentRss,
      };
      (report['checkpoints'] as List).add(row);
      lastCheckpointElapsed = cumulativeWriteMs;
      stdout.writeln(jsonEncode(row));
    }
    report['elapsedMs'] = total.elapsedMilliseconds;
    report['status'] = 'passed';
    final output = File('.dart_tool/current-capacity-profile.json');
    output.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    stdout.writeln('PASS ${output.path} ${total.elapsed}');
  } finally {
    await engine.lock();
    deleteSynthetic(work, root);
  }
}
