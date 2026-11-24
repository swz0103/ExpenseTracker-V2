import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/backup/model/backup_manager.dart';
import 'package:expense_tracker/src/features/reminders/model/reminder_alerts.dart';
import 'package:flutter_test/flutter_test.dart';

/// The day of [reviewLedger]: Thursday 8 October 2026, past the sixth day
/// a budget's forecast waits for, two days before the card below is due.
final reviewDay = DateTime.utc(2026, 10, 8);

/// The demo ledger with what the plain one leaves out, so the pages that
/// show it are looked at too: a 預定 expense and income (after today), a
/// spending partly given back by a refund, a broker account with its own
/// discount and a buy with its fee, a card due on 10 October, a holiday
/// (National Day, a Saturday), so its bill is moved to the next working
/// day (順延至), and a budget with its forecast showing.
Ledger reviewLedger() {
  final ledger = demoLedger(today: reviewDay);
  final spend = ledger.entries.all.firstWhere(
    (e) =>
        e.type == EntryType.expense &&
        e.account == 'bank' &&
        ledger.entryQueryService.refundable(e) > 50,
  );
  ledger.accountCommands
    ..addAccount(
      const Account(
        'broker',
        '永豐證券',
        AccountKind.bank,
        50000,
        brokerDiscount: 6000,
      ),
    )
    ..addAccount(
      const Account(
        'holiday-card',
        '國慶信用卡',
        AccountKind.card,
        -1200,
        closingDay: 25,
        dueDay: 10,
        limit: 50000,
      ),
    );
  ledger.entryCommands
    ..add(
      Entry(
        id: 'review-plan',
        date: DateTime.utc(2026, 10, 20),
        type: EntryType.expense,
        amount: 880,
        account: 'card',
        category: '飲食日常',
        note: '朋友聚餐訂位',
      ),
    )
    ..add(
      Entry(
        id: 'review-plan-income',
        date: DateTime.utc(2026, 10, 25),
        type: EntryType.income,
        amount: 3000,
        account: 'bank',
        category: '薪資收入',
        note: '獎金',
      ),
    )
    ..add(
      Entry(
        id: 'review-refund',
        date: DateTime.utc(2026, 10, 3),
        type: EntryType.income,
        amount: 50,
        account: spend.account,
        category: spend.category,
        refundOf: spend.id,
      ),
    )
    ..add(
      Entry(
        id: 'review-buy',
        date: DateTime.utc(2026, 10, 5),
        type: EntryType.buy,
        amount: 9000,
        account: 'broker',
        category: '',
        holding: '2330',
        shares: 10,
        fee: 20,
      ),
    );
  return ledger;
}

/// Keys of a ledger with a password, a fingerprint turned on and a
/// backup passphrase, as the settings show them.
final class ReviewKeys extends Fake implements BackupManager {
  @override
  bool get hasPassword => true;

  @override
  bool get canUseFingerprint => true;

  @override
  bool get fingerprintOn => true;

  @override
  bool get hasBackupPassphrase => true;

  @override
  bool get passwordBelowRule => false;

  @override
  String get passwordRule => '至少 8 個字';

  @override
  String? refusePassword(String password) => null;
}

/// A phone that allows what [status] says, and posts nothing.
final class ReviewPhone implements NotifyPort {
  ReviewPhone([
    this.allowed = (notifications: true, exact: true, battery: true),
  ]);

  final ReminderStatus allowed;

  @override
  Future<bool> access() async => true;

  @override
  Future<void> schedule(ReminderPlan plan) async {}

  @override
  Future<void> test({required bool exact}) async {}

  @override
  Future<void> post(Alert alert, int id) async {}

  @override
  Future<ReminderStatus> status() async => allowed;

  @override
  Future<void> openExactSettings() async {}

  @override
  Future<void> openBatterySettings() async {}
}
