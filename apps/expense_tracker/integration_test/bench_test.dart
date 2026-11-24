import 'dart:io';

import 'package:expense_tracker/src/app/app.dart';
import 'package:expense_tracker/src/core/ledger/persistence/journal_keeper.dart';
import 'package:expense_tracker/src/core/ledger/persistence/journal_rebuild.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/app/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_backup.dart';
import 'package:vault/ledger_vault.dart';

import '../test/support/held.dart';
import '../test/support/places.dart';

/// Times the app on an emulator in profile mode: writing and loading
/// three years of entries in the encrypted ledger, then switching tabs and
/// months, scrolling the records, opening the reports and saving one; the
/// memory the app holds then, and how long a backup of it takes. Run with
/// 3,600 entries (the figures kept since round 22), 10,000 (keys starting
/// `10k_`) and 100,000 (`100k_`). The emulator workflow prints them.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.reportData = {};

  testWidgets('three years of entries', (tester) async {
    await bench(binding, tester, count: 3600, key: (name) => name);
  });

  testWidgets('ten thousand entries', (tester) async {
    await bench(binding, tester, count: 10000, key: (name) => '10k_$name');
  });

  // Thirty years of a busy book: where memory and the backup are tested.
  testWidgets('a hundred thousand entries', (tester) async {
    await bench(binding, tester, count: 100000, key: (name) => '100k_$name');
  });
}

Future<void> bench(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester, {
  required int count,
  required String Function(String name) key,
}) async {
  final report = binding.reportData!;
  final directory = Directory.systemTemp.createTempSync('bench-');
  final vault = LedgerVault(
    directory,
    codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
  );
  final (open, _) = await vault.create('bench password');
  final dataSource = SqlLedgerDataSource(open.store);
  var ledger = await dataSource.load();
  final accounts = [
    for (final a in ledger.accounts.all)
      if (!a.kind.isDebt) a.id,
  ];
  final spending = [
    for (final c in ledger.categories.forEntries(income: false)) c.name,
  ];
  final earning = ledger.categories.forEntries(income: true).first.name;
  final today = ledger.today;
  final entries = [
    for (var i = 0; i < count; i++)
      Entry(
        id: ledger.newId(),
        date: today.subtract(Duration(days: (count - i) * 1095 ~/ count)),
        type: i % 30 == 0 ? EntryType.income : EntryType.expense,
        amount: i % 30 == 0 ? 52000 : 40 + i * 37 % 900,
        account: accounts[i % accounts.length],
        category: i % 30 == 0 ? earning : spending[i % spending.length],
        note: i.isEven ? '午餐' : '',
        tags: i % 7 == 0 ? const ['家用'] : const [],
      ),
  ];
  final writing = Stopwatch()..start();
  await dataSource.keep(WriteBatch(entries: entries));
  writing.stop();
  // The first opening after this version: every posting of the journal
  // made afresh from the records, on worker isolates, while the screen's
  // isolate only waits; the longest it was held then, in ms.
  final rebuilding = Stopwatch();
  final rebuilt = await timeHeld(() async {
    rebuilding.start();
    final posted = await open.store.postApart(
      postingWork(aside: const {}, start: const []),
      mark: (rules: journalRules, revision: open.store.revision),
    );
    rebuilding.stop();
    return posted;
  });
  expect(rebuilt.result.unposted, isEmpty, reason: 'every entry posted');
  report[key('journal_rebuild_ms')] = rebuilding.elapsedMilliseconds;
  report[key('journal_rebuild_held_ms')] = rebuilt.heldUs ~/ 1000;
  final loading = Stopwatch()..start();
  ledger = await dataSource.load();
  loading.stop();
  report[key('entries')] = count;
  report[key('write_ms')] = writing.elapsedMilliseconds;
  report[key('load_ms')] = loading.elapsedMilliseconds;
  // The memory the app holds with the book loaded, and the most it held
  // so far, in MiB.
  report[key('memory_mb')] = ProcessInfo.currentRss >> 20;
  report[key('memory_peak_mb')] = ProcessInfo.maxRss >> 20;
  // A backup of the whole book, as 設定 › 備份 makes one.
  final backingUp = Stopwatch()..start();
  await LedgerBackup.write(
    store: open.store,
    keys: open.keys,
    file: File('${directory.path}/bench.etbk'),
    backupId: 'bench',
    createdAt: DateTime.utc(2026, 10, 4),
  );
  backingUp.stop();
  report[key('backup_ms')] = backingUp.elapsedMilliseconds;
  report[key('backup_kb')] =
      File('${directory.path}/bench.etbk').lengthSync() >> 10;
  report[key('memory_peak_after_backup_mb')] = ProcessInfo.maxRss >> 20;

  await tester.pumpWidget(ExpenseApp(home: AppShell(ledger: ledger)));
  await tester.pumpAndSettle();
  Future<void> tap(String label) => go(tester, ['^$label']);

  Future<void> scroll() async {
    for (var i = 0; i < 4; i++) {
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, -600),
        2500,
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> tabs() async {
    for (final tab in ['紀錄', '帳戶', '更多', '總覽']) {
      await tap(tab);
    }
  }

  // Six months back on 總覽, each drawn in full.
  final months = Stopwatch();
  Future<void> monthsBack() async {
    months.start();
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byTooltip('上個月').first);
      await tester.pumpAndSettle();
    }
    months.stop();
  }

  await binding.watchPerformance(monthsBack, reportKey: key('months'));
  report[key('month_ms')] = months.elapsedMilliseconds ~/ 6;
  await binding.watchPerformance(tabs, reportKey: key('tabs'));
  await binding.watchPerformance(scroll, reportKey: key('overview_scroll'));
  await tap('紀錄');
  await binding.watchPerformance(scroll, reportKey: key('records_scroll'));
  await tap('更多');
  final opening = Stopwatch()..start();
  await tap('財務報表');
  opening.stop();
  report[key('reports_open_ms')] = opening.elapsedMilliseconds;
  await binding.watchPerformance(scroll, reportKey: key('reports'));

  // One entry saved while the records show: how long until the screen
  // shows it (what the person waits for), and how long until the store
  // has it (in the background), in microseconds, since both can be under
  // a millisecond. The entry must really be there afterwards, or the
  // figures mean nothing.
  final before = ledger.entries.length;
  final shown = Stopwatch();
  final kept = Stopwatch();
  Future<void> save() async {
    shown.start();
    kept.start();
    ledger.entryCommands.add(entries.first.withId(ledger.newId()));
    await tester.pumpAndSettle();
    shown.stop();
    await ledger.settled;
    kept.stop();
  }

  await tap('紀錄');
  await binding.watchPerformance(save, reportKey: key('save'));
  expect(ledger.entries.length, before + 1, reason: 'the entry was not added');
  expect(
    (await dataSource.load()).entries.length,
    before + 1,
    reason: 'the entry did not reach the store',
  );
  report[key('save_shown_us')] = shown.elapsedMicroseconds;
  report[key('save_kept_us')] = kept.elapsedMicroseconds;

  // The store's own share of a save, which the figures above hide behind
  // the screen's: 50 entries kept one at a time, each its own
  // transaction, timed on the thread that draws the screen. The median
  // and the slowest twentieth, in microseconds; a frame is 16,667.
  final each = <int>[];
  for (var i = 0; i < 50; i++) {
    final one = Stopwatch()..start();
    await dataSource.keep(
      WriteBatch(entries: [entries.first.withId(ledger.newId())]),
    );
    each.add(one.elapsedMicroseconds);
  }
  each.sort();
  report[key('keep_one_p50_us')] = each[25];
  report[key('keep_one_p95_us')] = each[47];
  report[key('keep_one_max_us')] = each.last;
  open.close();
  directory.deleteSync(recursive: true);
}
