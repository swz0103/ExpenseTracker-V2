import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/backup/model/backup_manager.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_export_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

/// Saves files into a list instead of the phone's Downloads, or fails.
final class _SavingBackupManager implements BackupManager {
  _SavingBackupManager({this.fails = false});

  final bool fails;
  final saved = <(String, String)>[];

  @override
  Future<bool> exportFile(String name, String text) async {
    if (fails) throw StateError('disk full');
    saved.add((name, text));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late Ledger ledger;
  setUp(() => ledger = demoLedger());

  Future<void> open(WidgetTester tester, {BackupManager? backups}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ImportExportSection(ledger: ledger, backupManager: backups),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await go(tester, ['匯出 CSV']);
    expect(find.text('匯出多少'), findsOneWidget);
  }

  int monthCount() =>
      ledger.entries.inMonth(ledger.today.year, ledger.today.month).length;

  /// Presses 匯出 N 筆 and lets the save finish.
  Future<void> export(WidgetTester tester, int count) async {
    await go(tester, ['匯出 $count 筆']);
    await tester.pumpAndSettle();
  }

  testWidgets('this month is chosen first, and saved under its month', (
    tester,
  ) async {
    final backups = _SavingBackupManager();
    await open(tester, backups: backups);
    final count = monthCount();
    expect(count, greaterThan(0));
    await export(tester, count);

    final (name, text) = backups.saved.single;
    expect(name, '記帳本-2026-10.csv');
    expect(text.trim().split('\n'), hasLength(count + 1));
    expect(find.text('已下載 $count 筆紀錄的 CSV'), findsOneWidget);
    expect(find.text('匯出多少'), findsNothing);
  });

  testWidgets('全部 and 今年 name the file for what they hold', (tester) async {
    final backups = _SavingBackupManager();
    await open(tester, backups: backups);
    await go(tester, ['全部']);
    await export(tester, ledger.entries.length);
    expect(backups.saved.last.$1, '記帳本-全部.csv');

    await go(tester, ['匯出 CSV', '今年']);
    final year = [
      for (final e in ledger.entries.all)
        if (e.date.year == ledger.today.year) e,
    ];
    await export(tester, year.length);
    expect(backups.saved.last.$1, '記帳本-2026.csv');
  });

  testWidgets('自訂 runs from the first of the month to today', (tester) async {
    final backups = _SavingBackupManager();
    await open(tester, backups: backups);
    await go(tester, ['自訂']);
    expect(find.text('從'), findsOneWidget);
    expect(find.text('到'), findsOneWidget);
    final count = [
      for (final e in ledger.entries.inMonth(2026, 10))
        if (!e.date.isAfter(ledger.today)) e,
    ].length;
    await export(tester, count);
    expect(backups.saved.single.$1, '記帳本-20261001-20261004.csv');
  });

  // Run under TZ=Asia/Taipei and TZ=America/New_York by CI as well: a
  // picked day is a UTC midnight, and comparing it as an instant with a
  // local midnight dropped the first day east of UTC, the last one west.
  testWidgets('自訂 from a picked day takes that day and today whole', (
    tester,
  ) async {
    final backups = _SavingBackupManager();
    await open(tester, backups: backups);
    await go(tester, ['自訂', '從', '前天']);
    final picked = [
      for (final e in ledger.entries.all)
        if (e.date.year == 2026 && e.date.month == 10 && e.date.day >= 2) e,
    ];
    // The demo book's days: 2 entries on the 2nd, 2 on the 3rd, 10 on the
    // 4th (today): 2 + 2 + 10 = 14.
    expect(picked, hasLength(14));
    await export(tester, 14);
    final (name, text) = backups.saved.single;
    expect(name, '記帳本-20261002-20261004.csv');
    // 14 rows under the heading row.
    expect(text.trim().split('\n'), hasLength(15));
  });

  testWidgets('without a way to save files, the CSV is copied', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await open(tester);
    final count = monthCount();
    await export(tester, count);
    expect(copied, isNotNull);
    expect(copied!.trim().split('\n'), hasLength(count + 1));
    expect(find.text('已複製 $count 筆紀錄的 CSV'), findsOneWidget);
  });

  testWidgets('a save that fails says so', (tester) async {
    await open(tester, backups: _SavingBackupManager(fails: true));
    await export(tester, monthCount());
    expect(find.textContaining('下載失敗：'), findsOneWidget);
  });

  testWidgets('匯入 offers a CSV file and e-invoices', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [ImportExportSection(ledger: ledger)]),
        ),
      ),
    );
    expect(find.text('CSV 檔案'), findsOneWidget);
    expect(find.text('電子發票'), findsOneWidget);
  });
}
