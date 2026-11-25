import 'package:expense_tracker/src/app/android/notification_adapter.dart';
import 'package:expense_tracker/src/core/diagnostics/error_log.dart';
import 'package:expense_tracker/src/core/platform/quick_action.dart';
import 'package:expense_tracker/src/features/reminders/model/reminder_alerts.dart';
import 'package:expense_tracker/src/features/reminders/model/reminder_rules.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the phone is handed: everything it posts, decided here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('expense_tracker/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final plan = ReminderPlan(const [], exact: false, wanted: const {});

  test('the plan goes with the most alerts the phone is to arm', () {
    // ReminderTiming.most: 160.
    expect(AndroidNotifications.planFields(plan)['most'], 160);
  });

  test('alerts the phone left out are recorded, not passed over', () async {
    Object? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call.arguments;
      // The phone armed all but 3.
      return 3;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final before = ErrorLog.instance.count;
    await const AndroidNotifications().schedule(plan);
    expect((sent! as Map)['most'], 160);
    expect(ErrorLog.instance.count - before, 1);
    // The log keeps no figures: the count reads #.
    expect(
      ErrorLog.instance.entries.first.$2,
      '通知：AlertsLeftOut: # alerts not armed',
    );
  });

  test('nothing is recorded when every alert was armed', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => 0);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final before = ErrorLog.instance.count;
    await const AndroidNotifications().schedule(plan);
    expect(ErrorLog.instance.count, before);
  });

  test('an alert goes with its wall-clock time, grace, channel and words', () {
    final alert = Alert(
      DateTime(2026, 11, 20, 9),
      '扣款：健身房 1,200',
      '定期交易，扣款帳戶：銀行',
      kind: ReminderKind.due,
      tag: 'due:r:gym:2026-11-20',
      confirms: ('gym', DateTime.utc(2026, 11, 20)),
    );
    final fields = AndroidNotifications.alertFields(alert)..remove('at');
    expect(fields, {
      'id': 'due|due:r:gym:2026-11-20|2026-11-20',
      'y': 2026,
      'm': 11,
      'd': 20,
      'hour': 9,
      'minute': 0,
      // 7 days: 7 × 24 × 60 × 60 × 1000 milliseconds.
      'grace': 604800000,
      'channel': 'due',
      'title': '扣款：健身房 1,200',
      'text': '定期交易，扣款帳戶：銀行',
      'quick': '',
      'tag': 'due:r:gym:2026-11-20',
      'recurring': 'gym',
      'day': '2026-11-20',
    });
  });

  test('the nudge opens the composer and confirms nothing', () {
    final fields = AndroidNotifications.alertFields(
      Alert(
        DateTime(2026, 11, 23, 21, 30),
        '今天記帳了嗎？',
        '點一下記一筆',
        kind: ReminderKind.nudge,
        quick: QuickAction.expense,
        tag: nudgeTag,
      ),
    );
    expect(
      (fields['channel'], fields['quick'], fields['grace'], fields['minute']),
      // 3 hours: 3 × 60 × 60 × 1000 milliseconds.
      ('nudge', 'expense', 10800000, 30),
    );
    expect(fields.containsKey('recurring'), isFalse);
  });

  test('AND-11: the channels go with their names', () {
    expect(AndroidNotifications.channels, [
      {'id': 'due', 'name': '到期提醒', 'about': '定期扣款、卡費到期'},
      {'id': 'nudge', 'name': '每日記帳提醒', 'about': '當天還沒記帳時提醒'},
      {'id': 'budget', 'name': '預算提醒', 'about': '預算用到警示比例或超支時'},
    ]);
  });
}
