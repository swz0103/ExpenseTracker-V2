import 'dart:io';

import 'package:backup_security/backup_security.dart';
import 'package:expense_tracker/src/app.dart';
import 'package:expense_tracker/src/book/vault_journal.dart';
import 'package:expense_tracker/src/model/ledger.dart';
import 'package:expense_tracker/src/pages/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ledger_vault/ledger_vault.dart';

/// Times the app on an emulator in profile mode: writing and loading
/// three years of entries in the encrypted ledger, then switching tabs,
/// scrolling the records and opening the reports. The emulator workflow
/// runs it and prints the timings.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('three years of entries', (tester) async {
    final directory = Directory.systemTemp.createTempSync('bench-');
    final vault = LedgerVault(
      directory,
      codec: KeyringCodec(kdf: PasswordKdf.insecureForTests),
    );
    final (open, _) = await vault.create('bench password');
    final journal = VaultJournal(open);
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
    const count = 3600;
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
    await journal.addEntries(entries);
    writing.stop();
    final loading = Stopwatch()..start();
    ledger = await journal.load();
    loading.stop();
    binding.reportData = {
      'entries': count,
      'write_ms': writing.elapsedMilliseconds,
      'load_ms': loading.elapsedMilliseconds,
    };

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

    Future<void> reports() async {
      await tap('財務報表');
      await scroll();
    }

    await binding.watchPerformance(tabs, reportKey: 'tabs');
    await binding.watchPerformance(scroll, reportKey: 'overview_scroll');
    await tap('紀錄');
    await binding.watchPerformance(scroll, reportKey: 'records_scroll');
    await tap('更多');
    await binding.watchPerformance(reports, reportKey: 'reports');

    // One entry saved while the records show: written, then the whole
    // book read back.
    final saving = Stopwatch();
    Future<void> save() async {
      saving.start();
      ledger.add(entries.first.withId(ledger.newId()));
      await ledger.settled;
      saving.stop();
      await tester.pumpAndSettle();
    }

    await tap('紀錄');
    await binding.watchPerformance(save, reportKey: 'save');
    binding.reportData!['save_ms'] = saving.elapsedMilliseconds;
    open.close();
    directory.deleteSync(recursive: true);
  });
}
