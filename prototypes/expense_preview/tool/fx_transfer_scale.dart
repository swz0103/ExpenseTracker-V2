import 'package:accounts/accounts.dart';

import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';

import '../test/support.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final root = Directory('.dart_tool/fx-transfer-scale')
    ..createSync(recursive: true);
  var work = root.createTempSync('source-');
  final vault = MemoryVault();
  var engine = engineAt(work, vault, schemaVersion: 8);
  final watch = Stopwatch()..start();
  final report = <String, Object>{
    'startedUtc': DateTime.now().toUtc().toIso8601String(),
  };
  try {
    final recovery = await setup(engine);
    final a = account(engine, name: 'source'),
        b = Account.open(
          id: PublicId.generate(),
          workspace: engine.workspace,
          name: 'destination',
          kind: AccountKind.bank,
          currency: Currency('JPY', 0),
          openedOn: a.openedOn,
        );
    await engine.createAccount(a, opening(a));
    await engine.createAccount(b, opening(b));
    final oldIncome = income(a, amount: '7');
    await engine.post(oldIncome);
    await engine.lock();
    engine = engineAt(work, vault, schemaVersion: 9);
    await engine.upgrade(password);
    var expectedA = BigInt.from(10700),
        expectedB = BigInt.from(100),
        feesA = BigInt.zero,
        feesB = BigInt.zero;
    final postings = <Posting>[oldIncome];
    for (var i = 0; i < 4997; i++) {
      final forward = i.isEven,
          units = BigInt.from(1 + i % 900),
          fee = BigInt.from(i % 4);
      final p = Posting.transfer(
        id: PublicId.generate(),
        operation: OperationKey(
          engine.workspace,
          OperationId(PublicId.generate()),
        ),
        date: BusinessDate(2026, 9, 27),
        source: ref(forward ? a : b),
        destination: ref(forward ? b : a),
        principal: Money(forward ? a.currency : b.currency, units),
        received: Money(
          forward ? b.currency : a.currency,
          units * BigInt.from(3) + BigInt.one,
        ),
        fee: Money(forward ? a.currency : b.currency, fee),
      );
      await engine.post(p);
      postings.add(p);
      final incoming = units * BigInt.from(3) + BigInt.one;
      if (forward) {
        expectedA -= units + fee;
        expectedB += incoming;
        feesA += fee;
      } else {
        expectedB -= units + fee;
        expectedA += incoming;
        feesB += fee;
      }
    }
    await engine.lock();
    engine = engineAt(work, vault, schemaVersion: 9);
    await engine.unlock(password);
    for (final p in postings) {
      await engine.post(p);
    }
    final before = await engine.exportBackup();
    final bytes = await EnvelopeCodec().openWithPassword(before, password);
    var rejected = false;
    try {
      await engine.post(income(a));
    } on PreviewCapacity {
      rejected = true;
    }
    check(rejected, '5001st event must reject');
    final after = await EnvelopeCodec().openWithPassword(
      await engine.exportBackup(),
      password,
    );
    check(utf8.decode(after) == utf8.decode(bytes), 'capacity rollback');
    final parsed = jsonDecode(utf8.decode(bytes)) as Map;
    final tables = parsed['tables'] as Map;
    check((tables['events'] as List).length == 5000, 'event count');
    for (final (code, fees) in [('TWD', feesA), ('JPY', feesB)]) {
      check(
        (tables['events'] as List)
                .where((e) => e['currency'] == code)
                .fold<BigInt>(
                  BigInt.zero,
                  (n, e) => n + BigInt.parse(e['expense'] as String),
                ) ==
            fees,
        'fees per currency',
      );
    }
    check(
      (tables['event_fx'] as List).length == 4997,
      'every FX relationship retained',
    );
    await engine.lock();
    deleteSynthetic(work, root);
    vault.values.clear();
    work = root.createTempSync('clean-restore-');
    for (final recover in [false, true]) {
      final target = Directory('${work.path}/$recover');
      final clean = MemoryVault();
      engine = engineAt(target, clean, schemaVersion: 9);
      await setup(engine);
      await engine.importBackup(
        before,
        recover ? recovery : password,
        recovery: recover,
      );
      await engine.lock();
      engine = engineAt(target, clean, schemaVersion: 9);
      await engine.unlock(password);
      final balances = await engine.accounts();
      check(
        balances.singleWhere((r) => r.account.id == a.id).balance.minorUnits ==
            expectedA,
        'source balance',
      );
      check(
        balances.singleWhere((r) => r.account.id == b.id).balance.minorUnits ==
            expectedB,
        'destination balance',
      );
      final restored = await EnvelopeCodec().openWithPassword(
        await engine.exportBackup(),
        password,
      );
      check(
        utf8.decode(restored) == utf8.decode(bytes),
        'complete snapshot after restore',
      );
      final ids = <PublicId>{};
      LedgerEntry? cursor;
      while (true) {
        final page = await engine.entries(before: cursor);
        if (page.isEmpty) break;
        for (final row in page) {
          check(ids.add(row.id), 'duplicate pagination');
          if (row.kind == PostingKind.transfer) {
            check(
              row.destinationId != null &&
                  row.fee != null &&
                  row.received != null &&
                  row.received!.currency != row.amount.currency,
              'complete transfer detail',
            );
          }
        }
        cursor = page.last;
      }
      check(ids.length == 5000, 'complete pagination');
      await engine.lock();
    }
    report.addAll({
      'status': 'passed',
      'events': 5000,
      'transfers': 4997,
      'replayed': postings.length,
      'snapshotBytes': bytes.length,
      'rows': tables.values.fold<int>(0, (n, r) => n + (r as List).length),
      'sourceMinor': expectedA.toString(),
      'destinationMinor': expectedB.toString(),
      'feeMinorByCurrency': {'TWD': feesA.toString(), 'JPY': feesB.toString()},
      'schema8Upgrade': true,
      'originalKeysDeleted': true,
      'passwordCleanRestore': true,
      'recoveryCleanRestore': true,
      'paginatedEntriesPerRestore': 5000,
      'elapsedMs': watch.elapsedMilliseconds,
    });
    await File(
      '.dart_tool/fx-transfer-scale-report.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    stdout.writeln(jsonEncode(report));
  } finally {
    await engine.lock();
    deleteSynthetic(work, root);
  }
}
