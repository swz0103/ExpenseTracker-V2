import 'dart:io';

import 'package:expense_tracker/src/app/app.dart';
import 'package:expense_tracker/src/core/ledger/table_journal.dart';
import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/app/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

/// Times the app on an emulator in profile mode: writing and loading
/// three years of entries in the encrypted ledger, then switching tabs and
/// months, scrolling the records, opening the reports and saving one. Run
/// with 3,600 entries (the figures kept since round 22) and with 10,000
/// (keys starting `10k_`). The emulator workflow prints the timings.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.reportData = {};

  testWidgets('three years of entries', (tester) async {
    await bench(binding, tester, count: 3600, key: (name) => name);
  });

  testWidgets('ten thousand entries', (tester) async {
    await bench(binding, tester, count: 10000, key: (name) => '10k_$name');
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
  final journal = TableJournal(open.store);
  var ledger = await journal.load();
  final accounts = [
    for (final a in ledger.accounts)
      if (!a.kind.isDebt) a.id,
  ];
  final spending = [
    for (final c in ledger.categoriesFor(income: false)) c.name,
  ];
  final earning = ledger.categoriesFor(income: true).first.name;
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
  await journal.keep(Batch(entries: entries));
  writing.stop();
  final loading = Stopwatch()..start();
  ledger = await journal.load();
  loading.stop();
  report[key('entries')] = count;
  report[key('write_ms')] = writing.elapsedMilliseconds;
  report[key('load_ms')] = loading.elapsedMilliseconds;

  await tester.pumpWidget(ExpenseApp(home: AppShell(ledger: ledger)));
  await tester.pumpAndSettle();
  Future<void> tap(String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

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
  await tester.tap(find.byTooltip('返回').first);
  await tester.pumpAndSettle();

  // One entry saved while the records show.
  final saving = Stopwatch();
  Future<void> save() async {
    saving.start();
    ledger.add(entries.first.withId(ledger.newId()));
    await ledger.settled;
    saving.stop();
    await tester.pumpAndSettle();
  }

  await tap('紀錄');
  await binding.watchPerformance(save, reportKey: key('save'));
  report[key('save_ms')] = saving.elapsedMilliseconds;
  open.close();
  directory.deleteSync(recursive: true);
}
