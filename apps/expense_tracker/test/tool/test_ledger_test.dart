import 'dart:io';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/sql_ledger_data_source.dart';
import 'package:expense_tracker/src/features/backup/model/encrypted_backup_manager.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/backup_security.dart';
import 'package:vault/ledger_vault.dart';

/// The test backup people restore to try the app with real-looking data:
/// the two years of tool/test_ledger.py imported as its CSV would be, on
/// accounts set up first (cards with their days and limits, the foreign
/// accounts, the car loan), with budgets and recurring items added and the
/// old salary account archived; kept as a backup that opens with
/// [password]. Every line must import. With
/// TEST_BACKUP_OUT set, as the APK build does, the backup is copied
/// there to be published beside the APK.
void main() {
  const password = 'test1234';

  test('the test ledger imports in full and its backup opens with '
      '$password', () async {
    final work = Directory.systemTemp.createTempSync('test-ledger-');
    addTearDown(() => work.deleteSync(recursive: true));
    final csv = File('${work.path}/ledger.csv');
    final made = await Process.run('python3', [
      'tool/test_ledger.py',
      csv.path,
    ]);
    expect(made.exitCode, 0, reason: '${made.stderr}');

    // The app's own codec: a password of 6 or more, the real key work.
    Startup startupIn(String name) => Startup(
      LedgerVault(
        Directory('${work.path}/$name'),
        codec: KeyringCodec(minimumPassword: 6),
      ),
      check: SqlLedgerDataSource.check,
    );
    final startup = startupIn('made');
    await startup.setUp(password);
    final vault = (startup.state as Ready).vault;
    final ledger = await SqlLedgerDataSource(vault.store).load();
    _setUp(ledger);
    final text = await csv.readAsString();
    final found = importCsv(ledger, text, fallback: '');
    expect(found.skipped, 0, reason: found.problems.join('\n'));
    final lines = text.trim().split('\n').length - 1;
    expect(found.entries, hasLength(lines));
    expect(lines, greaterThan(2000));
    addImport(ledger, found);
    _settle(ledger);
    await ledger.settled;
    expect(ledger.problem.value, isNull);

    final backupManager = EncryptedBackupManager(startup, vault);
    final backup = await backupManager.backUp();
    await backupManager.lock();

    final phone = startupIn('restored');
    await phone.restore(backup, password);
    expect(phone.state, isA<Ready>());
    final restored = await SqlLedgerDataSource(
      (phone.state as Ready).vault.store,
    ).load();
    expect(restored.entries.all, hasLength(ledger.entries.length));
    phone.lock();

    final out = Platform.environment['TEST_BACKUP_OUT'];
    if (out != null && out.isNotEmpty) File(backup).copySync(out);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// The accounts the CSV needs more than a name for, made before it is
/// read so its lines land on them.
void _setUp(Ledger ledger) {
  Account made(
    String name,
    AccountKind kind, {
    int opening = 0,
    int? closingDay,
    int? dueDay,
    int? limit,
    String currency = homeCode,
    int? principal,
    LoanTerms? loan,
  }) => Account(
    ledger.newId(),
    name,
    kind,
    opening,
    closingDay: closingDay,
    dueDay: dueDay,
    limit: limit,
    currency: currency,
    principal: principal,
    loan: loan,
  );
  for (final account in [
    made('國泰信用卡', AccountKind.card, closingDay: 5, dueDay: 20, limit: 150000),
    made('玉山信用卡', AccountKind.card, closingDay: 15, dueDay: 3, limit: 80000),
    made('台新信用卡', AccountKind.card, closingDay: 25, dueDay: 13, limit: 60000),
    made('美元帳戶', AccountKind.bank, currency: 'USD'),
    made('日圓帳戶', AccountKind.bank, currency: 'JPY'),
    made(
      '車貸',
      AccountKind.loan,
      opening: -480000,
      principal: 480000,
      dueDay: 25,
      loan: const LoanTerms(rate: 260, months: 60, repay: LoanRepay.even),
    ),
  ]) {
    ledger.accountCommands.addAccount(account);
  }
}

/// What the CSV cannot carry: budgets, recurring items, and the old
/// salary account archived once emptied.
void _settle(Ledger ledger) {
  String id(String name) =>
      ledger.accounts.all.firstWhere((a) => a.name == name).id;
  for (final (category, limit) in [
    (allSpending, 38000),
    ('飲食日常', 12000),
    ('居家生活', 16000),
    ('交通通勤', 4500),
    ('購物休閒', 6000),
    ('訂閱服務', 900),
    ('寵物', 1500),
  ]) {
    ledger.budgetCommands.setBudget(category, limit);
  }
  for (final item in [
    Recurring(
      id: 'rent',
      name: '房租',
      amount: 12500,
      day: 1,
      account: id('台新銀行'),
      category: '居家生活',
      merchant: '房東',
    ),
    Recurring(
      id: 'salary',
      name: '薪資',
      amount: 55000,
      day: 5,
      account: id('台新銀行'),
      category: '薪資收入',
      income: true,
      auto: true,
    ),
    Recurring(
      id: 'netflix',
      name: 'Netflix',
      amount: 390,
      day: 8,
      account: id('國泰信用卡'),
      category: '訂閱服務',
      merchant: 'Netflix',
    ),
    Recurring(
      id: 'spotify',
      name: 'Spotify',
      amount: 149,
      day: 12,
      account: id('玉山信用卡'),
      category: '訂閱服務',
      merchant: 'Spotify',
    ),
    Recurring(
      id: 'phone',
      name: '手機費',
      amount: 599,
      day: 18,
      account: id('國泰世華'),
      category: '居家生活',
    ),
    Recurring(
      id: 'car-insurance',
      name: '汽車保險',
      amount: 12800,
      day: 15,
      account: id('國泰世華'),
      category: '保險',
      unit: RepeatUnit.year,
      start: DateTime.utc(2027, 3, 15),
    ),
    Recurring(
      id: 'gym',
      name: '健身房',
      amount: 999,
      day: 28,
      account: id('台新信用卡'),
      category: '購物休閒',
      active: false,
    ),
  ]) {
    ledger.recurringCommands.saveRecurring(item);
  }
  final old = ledger.account(id('舊薪轉帳戶'));
  ledger.accountCommands.updateAccount(old.copyWith(archived: true));
}
