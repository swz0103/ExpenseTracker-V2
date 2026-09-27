import 'dart:convert';
import 'dart:io';

import 'package:backup_envelope_probe/envelope.dart';
import 'package:categories/categories.dart';
import 'package:expense_preview/preview_engine.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';

import '../test/support.dart';

void check(bool condition, String name) {
  if (!condition) throw StateError(name);
}

Future<void> main() async {
  final root = Directory('.dart_tool/split-scale')..createSync(recursive: true);
  var work = root.createTempSync('source-');
  final vault = MemoryVault();
  var engine = engineAt(work, vault, schemaVersion: 8);
  final watch = Stopwatch()..start();
  final report = <String, Object>{
    'startedUtc': DateTime.now().toUtc().toIso8601String(),
  };
  try {
    final recovery = await setup(engine), a = account(engine);
    await engine.createAccount(a, opening(a));
    final incomeCats = List.generate(16, (_) => PublicId.generate()),
        expenseCats = List.generate(16, (_) => PublicId.generate());
    OperationKey op() =>
        OperationKey(engine.workspace, OperationId(PublicId.generate()));
    for (var i = 0; i < 16; i++) {
      await engine.createCategory(
        op(),
        incomeCats[i],
        'Income $i',
        CategoryKind.income,
      );
      await engine.createCategory(
        op(),
        expenseCats[i],
        'Expense $i',
        CategoryKind.expense,
      );
    }
    final pending = await engine.saveEntryDraft(
      EntryFields(
        income: false,
        split: true,
        amount: '10',
        date: '2026-09-28',
        accountId: a.id,
        splits: [
          SplitFields(categoryId: expenseCats[0], amount: '3.25'),
          SplitFields(categoryId: expenseCats[1], amount: '6.75'),
        ],
      ),
    );
    await engine.lock();
    final target = engineAt(work, vault, schemaVersion: 9);
    var blocked = false;
    try {
      await target.upgrade(password);
    } on DraftNeedsResolution {
      blocked = true;
    }
    check(blocked, 'upgrade must preserve pending split');
    await target.lock();
    await engine.unlock(password);
    check(
      (await engine.entryDraft())!.encode() == pending.encode(),
      'unchanged draft before upgrade',
    );
    await engine.submitEntryDraft();
    await engine.lock();
    engine = engineAt(work, vault, schemaVersion: 9);
    await engine.upgrade(password);
    check(
      (await engine.allocations(pending.id)).length == 2,
      'split survives schema 8 to 9',
    );
    var expected = BigInt.from(9000),
        incomeTotal = BigInt.zero,
        expenseTotal = BigInt.from(1000);
    final postings = <Posting>[];
    final byCategory = <String, BigInt>{
      expenseCats[0].value: BigInt.from(325),
      expenseCats[1].value: BigInt.from(675),
    };
    for (var i = 0; i < 4998; i++) {
      final inc = i.isEven,
          cats = inc ? incomeCats : expenseCats,
          n = i % 100 == 0 ? 16 : 2;
      final allocations = <Allocation>[];
      var total = BigInt.zero;
      for (var j = 0; j < n; j++) {
        final amount = BigInt.from(1 + (i + j) % 73);
        total += amount;
        allocations.add(
          Allocation(
            cats[j],
            Money(a.currency, amount),
            expectedCategoryVersion: 1,
          ),
        );
        byCategory[cats[j].value] =
            (byCategory[cats[j].value] ?? BigInt.zero) + amount;
      }
      final factory = inc ? Posting.income : Posting.expense;
      final p = factory(
        id: PublicId.generate(),
        operation: op(),
        date: BusinessDate(2026, 9, 28),
        account: ref(a),
        amount: Money(a.currency, total),
        allocations: allocations,
      );
      await engine.post(p);
      postings.add(p);
      if (inc) {
        expected += total;
        incomeTotal += total;
      } else {
        expected -= total;
        expenseTotal += total;
      }
    }
    await engine.lock();
    engine = engineAt(work, vault, schemaVersion: 9);
    await engine.unlock(password);
    for (final posting in postings) {
      await engine.post(posting);
    }
    final backup = await engine.exportBackup(),
        bytes = await EnvelopeCodec().openWithPassword(backup, password);
    var rejected = false;
    try {
      await engine.post(income(a));
    } on PreviewCapacity {
      rejected = true;
    }
    check(rejected, '5001st event rejects');
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
    check(
      (tables['events'] as List).length == 5000 &&
          (tables['legs'] as List).length == 5000,
      'split never duplicates financial legs',
    );
    for (final (key, total) in [
      ('income', incomeTotal),
      ('expense', expenseTotal),
    ]) {
      check(
        (tables['events'] as List).fold<BigInt>(
              BigInt.zero,
              (n, e) => n + BigInt.parse(e[key] as String),
            ) ==
            total,
        'independent $key',
      );
    }
    final actualCategories = <String, BigInt>{};
    for (final r in tables['allocations'] as List) {
      final id = r['category_id'] as String;
      actualCategories[id] =
          (actualCategories[id] ?? BigInt.zero) +
          BigInt.parse(r['amount'] as String);
    }
    check(
      actualCategories.length == byCategory.length &&
          byCategory.entries.every((e) => actualCategories[e.key] == e.value),
      'independent category totals',
    );
    await engine.lock();
    deleteSynthetic(work, root);
    vault.values.clear();
    work = root.createTempSync('restored-');
    for (final rescue in [false, true]) {
      final clean = MemoryVault(), dir = Directory('${work.path}/$rescue');
      engine = engineAt(dir, clean, schemaVersion: 9);
      await setup(engine);
      await engine.importBackup(
        backup,
        rescue ? recovery : password,
        recovery: rescue,
      );
      await engine.lock();
      engine = engineAt(dir, clean, schemaVersion: 9);
      await engine.unlock(password);
      check(
        (await engine.accounts()).single.balance.minorUnits == expected,
        'restored balance',
      );
      check(
        utf8.decode(
              await EnvelopeCodec().openWithPassword(
                await engine.exportBackup(),
                password,
              ),
            ) ==
            utf8.decode(bytes),
        'full restored snapshot',
      );
      final ids = <PublicId>{};
      LedgerEntry? cursor;
      while (true) {
        final page = await engine.entries(before: cursor);
        if (page.isEmpty) break;
        for (final e in page) {
          check(ids.add(e.id), 'unique page entry');
        }
        cursor = page.last;
      }
      check(ids.length == 5000, 'complete pagination');
      await engine.lock();
    }
    report.addAll({
      'status': 'passed',
      'events': 5000,
      'splitTransactions': 4999,
      'sixteenWaySplits': 50,
      'replayed': postings.length,
      'rows': tables.values.fold<int>(0, (n, r) => n + (r as List).length),
      'snapshotBytes': bytes.length,
      'balanceMinor': expected.toString(),
      'incomeMinor': incomeTotal.toString(),
      'expenseMinor': expenseTotal.toString(),
      'allocationRows': (tables['allocations'] as List).length,
      'categoryTotals': {
        for (final e in byCategory.entries) e.key: e.value.toString(),
      },
      'pendingDraftUpgradeBlocked': true,
      'resolvedSplitSchema8Upgrade': true,
      'originalKeysDeleted': true,
      'passwordCleanRestore': true,
      'recoveryCleanRestore': true,
      'paginatedEntriesPerRestore': 5000,
      'elapsedMs': watch.elapsedMilliseconds,
    });
    await File(
      '.dart_tool/split-scale-report.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    stdout.writeln(jsonEncode(report));
  } finally {
    await engine.lock();
    deleteSynthetic(work, root);
  }
}
