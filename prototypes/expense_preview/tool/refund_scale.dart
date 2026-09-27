import 'dart:convert';
import 'dart:io';

import 'package:accounts/accounts.dart';
import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';

import '../test/support.dart';

void check(bool ok, String what) {
  if (!ok) throw StateError(what);
}

Future<void> main() async {
  final root = Directory('.dart_tool/refund-scale')
    ..createSync(recursive: true);
  var work = root.createTempSync('source-');
  final vault = MemoryVault();
  var engine = engineAt(work, vault, schemaVersion: 9);
  final watch = Stopwatch()..start(),
      started = DateTime.now().toUtc().toIso8601String();
  try {
    final recovery = await setup(engine), a = account(engine);
    await engine.createAccount(a, opening(a));
    final b = Account.open(
      id: PublicId.generate(),
      workspace: engine.workspace,
      name: 'JPY',
      kind: AccountKind.bank,
      currency: Currency('JPY', 0),
      openedOn: a.openedOn,
    );
    await engine.createAccount(b, opening(b));
    OperationKey op() =>
        OperationKey(engine.workspace, OperationId(PublicId.generate()));
    final category = PublicId.generate();
    await engine.createCategory(
      op(),
      category,
      'Expense',
      CategoryKind.expense,
    );
    final originals = <Posting>[];
    for (var i = 0; i < 2; i++) {
      final p = Posting.expense(
        id: PublicId.generate(),
        operation: op(),
        date: BusinessDate(2026, 9, 27),
        account: ref(a),
        amount: Money.parse(a.currency, '25'),
        allocations: [
          Allocation(
            category,
            Money.parse(a.currency, '25'),
            expectedCategoryVersion: 1,
          ),
        ],
      );
      await engine.post(p);
      originals.add(p);
    }
    await engine.lock();
    engine = engineAt(work, vault, schemaVersion: 10);
    await engine.upgrade(password);
    final postings = <Posting>[];
    for (var i = 0; i < 4996; i++) {
      final foreign = i.isOdd;
      final p = Posting.refund(
        id: PublicId.generate(),
        operation: op(),
        date: BusinessDate(2026, 9, 28),
        account: ref(foreign ? b : a),
        originalId: originals[i % 2].id,
        amount: Money.parse(a.currency, '0.01'),
        received: foreign ? Money.parse(b.currency, '2') : null,
        allocations: [
          Allocation(
            category,
            Money.parse(a.currency, '0.01'),
            expectedCategoryVersion: 1,
          ),
        ],
      );
      await engine.post(p);
      postings.add(p);
      if ((i + 1) % 1000 == 0) {
        stdout.writeln(
          'Refunds ${i + 1}; elapsed ${watch.elapsedMilliseconds} ms',
        );
      }
    }
    final writtenMs = watch.elapsedMilliseconds;
    await engine.lock();
    engine = engineAt(work, vault, schemaVersion: 10);
    await engine.unlock(password);
    for (final p in postings) {
      await engine.post(p);
    }
    final backup = await engine.exportBackup(),
        bytes = await EnvelopeCodec().openWithPassword(backup, password);
    var rejected = false;
    try {
      await engine.post(income(a));
    } on PreviewCapacity {
      rejected = true;
    }
    check(rejected, 'event cap');
    check(
      utf8.decode(
            await EnvelopeCodec().openWithPassword(
              await engine.exportBackup(),
              password,
            ),
          ) ==
          utf8.decode(bytes),
      'capacity rollback',
    );
    final tables = (jsonDecode(utf8.decode(bytes)) as Map)['tables'] as Map;
    check((tables['events'] as List).length == 5000, 'event count');
    check((tables['event_refunds'] as List).length == 4996, 'refund count');
    check((tables['event_fx'] as List).length == 2498, 'FX count');
    check(
      (tables['events'] as List).fold<BigInt>(
            BigInt.zero,
            (sum, e) => sum + BigInt.parse(e['expense'] as String),
          ) ==
          BigInt.from(4),
      'independent negative expense sum',
    );
    check(
      (tables['events'] as List).every((e) => e['income'] == '0'),
      'no refund income',
    );
    final kinds = {
      for (final e in tables['events'] as List) e['id']: e['kind'],
    };
    check(
      (tables['allocations'] as List).fold<BigInt>(
            BigInt.zero,
            (sum, r) =>
                sum +
                (kinds[r['event_id']] == 'refund'
                    ? -BigInt.parse(r['amount'] as String)
                    : BigInt.parse(r['amount'] as String)),
          ) ==
          BigInt.from(4),
      'independent signed category',
    );
    await engine.lock();
    deleteSynthetic(work, root);
    vault.values.clear();
    work = root.createTempSync('restored-');
    for (final rescue in [false, true]) {
      engine = engineAt(
        Directory('${work.path}/$rescue'),
        MemoryVault(),
        schemaVersion: 10,
      );
      await setup(engine);
      await engine.importBackup(
        backup,
        rescue ? recovery : password,
        recovery: rescue,
      );
      final accounts = await engine.accounts();
      check(
        accounts.singleWhere((r) => r.account.id == a.id).balance.minorUnits ==
            BigInt.from(7498),
        'source cash',
      );
      check(
        accounts.singleWhere((r) => r.account.id == b.id).balance.minorUnits ==
            BigInt.from(5096),
        'foreign cash',
      );
      for (final original in originals) {
        check(
          (await engine.refundStatus(original.id))
                  .budget
                  .remaining
                  .minorUnits ==
              BigInt.from(2),
          'remaining original limit',
        );
      }
      check(
        utf8.decode(
              await EnvelopeCodec().openWithPassword(
                await engine.exportBackup(),
                password,
              ),
            ) ==
            utf8.decode(bytes),
        'canonical clean restore',
      );
      final ids = <PublicId>{};
      LedgerEntry? cursor;
      while (true) {
        final page = await engine.entries(before: cursor);
        if (page.isEmpty) break;
        for (final e in page) {
          check(ids.add(e.id), 'pagination uniqueness');
          if (e.kind == PostingKind.refund) {
            check(
              e.refundOf != null && e.refunded!.minorUnits == BigInt.one,
              'refund detail',
            );
          }
        }
        cursor = page.last;
      }
      check(ids.length == 5000, 'complete pagination');
      await engine.lock();
    }
    final report = {
      'status': 'passed',
      'startedUtc': started,
      'events': 5000,
      'refunds': 4996,
      'fxRefunds': 2498,
      'replayed': postings.length,
      'expenseMinor': '4',
      'sourceCashMinor': '7498',
      'receivedCashMinor': '5096',
      'remainingPerSourceMinor': '2',
      'snapshotBytes': bytes.length,
      'rows': tables.values.fold<int>(0, (n, r) => n + (r as List).length),
      'originalKeysDeleted': true,
      'passwordCleanRestore': true,
      'recoveryCleanRestore': true,
      'schema9To10': true,
      'writesMs': writtenMs,
      'elapsedMs': watch.elapsedMilliseconds,
    };
    await File(
      '.dart_tool/refund-scale-report.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    stdout.writeln(jsonEncode(report));
  } finally {
    await engine.lock();
    deleteSynthetic(work, root);
  }
}
