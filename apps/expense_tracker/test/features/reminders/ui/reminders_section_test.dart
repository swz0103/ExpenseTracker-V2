import 'dart:io';

import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/design_system/display/date.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/reminders/model/calendar_sync.dart';
import 'package:expense_tracker/src/features/reminders/model/reminder_alerts.dart';
import 'package:expense_tracker/src/features/reminders/model/reminders.dart';
import 'package:expense_tracker/src/features/reminders/ui/reminders_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

/// 通知與提醒 on a phone stood in for: turning each kind of notification
/// on asks the phone first, the strip under the cards says what the phone
/// still holds back and opens where to change it, each card's details
/// (what falls due, the budgets, the daily time, 準時提醒), and linking,
/// changing and dropping a calendar, with what is written to it.
void main() {
  setUpAll(loadFonts);

  late Ledger ledger;
  late Preferences preferences;
  late _Phone phone;
  late _Calendars calendars;
  late Directory directory;
  late CalendarSync calendar;
  late int budgetsOpened;

  setUp(() {
    ledger = demoLedger();
    // Budget warnings are on until turned off; here everything starts off.
    preferences = Preferences()..update(budgetAlerts: false);
    phone = _Phone();
    calendars = _Calendars();
    directory = Directory.systemTemp.createTempSync('reminders-section-');
    calendar = CalendarSync(calendars, directory);
    budgetsOpened = 0;
  });

  tearDown(() => directory.deleteSync(recursive: true));

  Future<void> put(
    WidgetTester tester, {
    bool notifications = true,
    bool withCalendar = true,
  }) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // As 設定 does, drawn again as the preferences change.
              ListenableBuilder(
                listenable: preferences,
                builder: (context, _) => RemindersSection(
                  ledger: ledger,
                  notifier: notifications ? Notifier(phone, preferences) : null,
                  calendar: withCalendar ? calendar : null,
                  onBudgets: () => budgetsOpened++,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lets the calendar's file be written and read, drawing, until [done].
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 50 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
  }

  testWidgets('ticking 到期提醒 asks the phone first, and once allowed '
      'turns it on and shows the phone is ready', (tester) async {
    await put(tester);
    expect(find.text('手機設定都好了'), findsNothing, reason: 'none asked');
    await go(tester, ['到期提醒']);
    expect(phone.asked, 1);
    expect(preferences.dueAlerts, isTrue);
    expect(find.text('手機設定都好了'), findsOneWidget);

    // Turning it off again needs no asking.
    await go(tester, ['到期提醒']);
    expect(phone.asked, 1);
    expect(preferences.dueAlerts, isFalse);
    expect(find.text('手機設定都好了'), findsNothing);
  });

  testWidgets('a phone that does not allow notifications leaves them off '
      'and says where to turn them on', (tester) async {
    phone.allows = false;
    await put(tester);
    await go(tester, ['預算提醒']);
    expect(preferences.budgetAlerts, isFalse);
    expect(find.text('沒有取得通知權限，可以到系統設定開啟'), findsOneWidget);
  });

  testWidgets('a phone that fails when asked is taken as a no', (tester) async {
    phone.fails = true;
    await put(tester);
    await go(tester, ['每日記帳']);
    expect(preferences.dailyNudge, isFalse);
    expect(find.text('沒有取得通知權限，可以到系統設定開啟'), findsOneWidget);
  });

  testWidgets('試一則 sends a test notification, on the minute when asked '
      'to be, and says when it comes', (tester) async {
    preferences.update(dueAlerts: true, exactReminders: true);
    await put(tester);
    await go(tester, ['試一則']);
    expect(phone.tests, [true]);
    expect(find.text('一分鐘後會跳出一則測試通知'), findsOneWidget);
  });

  testWidgets('a test that cannot be sent says why', (tester) async {
    preferences.update(dueAlerts: true);
    phone.testFails = true;
    await put(tester);
    await go(tester, ['試一則']);
    expect(find.textContaining('無法傳送測試通知：'), findsOneWidget);
  });

  testWidgets('with notifications off on the phone, the strip says so and '
      '去開 asks again', (tester) async {
    preferences.update(dueAlerts: true);
    phone.allowed = (notifications: false, exact: true, battery: true);
    await put(tester);
    expect(find.text('通知權限沒開'), findsOneWidget);
    phone.allows = false;
    await go(tester, ['去開']);
    expect(phone.asked, 1);
    expect(find.text('請到系統設定開啟記帳本的通知'), findsOneWidget);

    // Allowed in the system settings, read again on coming back.
    phone.allowed = (notifications: true, exact: true, battery: true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('手機設定都好了'), findsOneWidget);
  });

  testWidgets('alarms not allowed matter only for reminders on the minute; '
      '去開 opens their settings', (tester) async {
    preferences.update(dailyNudge: true);
    phone.allowed = (notifications: true, exact: false, battery: true);
    await put(tester);
    expect(find.text('手機設定都好了'), findsOneWidget);

    preferences.update(exactReminders: true);
    await tester.pumpAndSettle();
    expect(find.text('鬧鐘與提醒沒開'), findsOneWidget);
    await go(tester, ['去開']);
    expect(phone.opened, ['exact']);
  });

  testWidgets('battery saving that may hold reminders back is named, and '
      '去開 opens its settings', (tester) async {
    preferences.update(budgetAlerts: true);
    phone.allowed = (notifications: true, exact: true, battery: false);
    await put(tester);
    expect(find.text('電池最佳化可能延後提醒'), findsOneWidget);
    await go(tester, ['去開']);
    expect(phone.opened, ['battery']);
  });

  testWidgets('到期提醒\'s details list what falls due in the next 30 days', (
    tester,
  ) async {
    await put(tester);
    await go(tester, ['信用卡、定期交易']);
    expect(find.text('接下來會提醒'), findsOneWidget);
    final coming = reminderBookOf(ledger).reminders(days: 30).take(4).toList();
    expect(coming, isNotEmpty);
    for (final r in coming) {
      expect(find.text(r.title), findsWidgets);
      expect(find.text(formatMd(r.day)), findsWidgets);
    }
    // The panel's own tick turns them on as the card's does.
    await go(tester, ['^到期提醒']);
    expect(preferences.dueAlerts, isTrue);
  });

  testWidgets('預算提醒\'s details show each budget\'s warning, and lead to '
      '預算管理', (tester) async {
    await put(tester);
    await go(tester, ['用到幾成時']);
    expect(find.text('現在的設定'), findsOneWidget);
    expect(find.text('總預算 80%'), findsOneWidget);
    expect(find.text('飲食日常 80%'), findsOneWidget);
    await go(tester, ['到預算管理改比例 ›']);
    expect(budgetsOpened, 1);
    expect(find.text('現在的設定'), findsNothing, reason: 'closed');
  });

  testWidgets('a book with no budgets says so in 預算提醒', (tester) async {
    for (final b in [...ledger.budgets.all]) {
      ledger.budgetCommands.removeBudget(b.category);
    }
    await put(tester);
    await go(tester, ['用到幾成時']);
    expect(find.text('還沒有設定預算'), findsOneWidget);
  });

  testWidgets('每日記帳\'s time is chosen in its details and shown on the '
      'card', (tester) async {
    await put(tester);
    expect(find.text('每天 21:00'), findsOneWidget);
    await go(tester, ['每天 21:00']);
    expect(find.text('21 : 00'), findsOneWidget);
    await go(tester, ['提醒時間：21:00']);
    expect(find.text('每天幾點提醒'), findsOneWidget);
    await go(tester, ['08:00', '確定']);
    expect((preferences.nudgeHour, preferences.nudgeMinute), (8, 0));
    expect(find.text('08 : 00'), findsOneWidget);
  });

  testWidgets('準時提醒 turned on with alarms not allowed opens their '
      'settings, and the card says 準時', (tester) async {
    phone.allowed = (notifications: true, exact: false, battery: true);
    await put(tester);
    await go(tester, ['每天 21:00', '準時提醒']);
    expect(preferences.exactReminders, isTrue);
    expect(phone.opened, ['exact']);
    expect(find.text('請在接下來的畫面允許「鬧鐘與提醒」'), findsOneWidget);
    expect(find.text('每天 21:00 · 準時'), findsOneWidget);
  });

  testWidgets('without a phone to notify, only the calendar is offered', (
    tester,
  ) async {
    await put(tester, notifications: false);
    expect(find.text('到期提醒'), findsNothing);
    expect(find.text('Google 日曆'), findsOneWidget);
    await put(tester, notifications: false, withCalendar: false);
    expect(find.text('Google 日曆'), findsNothing);
  });

  testWidgets('linking a calendar writes what falls due into the one '
      'picked, and says how many', (tester) async {
    await put(tester);
    await go(tester, ['提醒定期扣款與卡費']);
    expect(find.text('同步到哪個日曆'), findsOneWidget);
    expect(find.text('me@example.com'), findsOneWidget);
    await go(tester, ['家庭']);
    await settle(tester, () => find.textContaining('已把').evaluate().isNotEmpty);
    expect(calendar.chosen, (2, '家庭'));
    final written = calendars.written[2]!;
    expect(written, isNotEmpty);
    expect(find.text('已把 ${written.length} 個到期提醒放進日曆'), findsOneWidget);
    expect(find.text('已連結 · 寫金額'), findsOneWidget);
  });

  testWidgets('a calendar not allowed, or none on the phone, is said so', (
    tester,
  ) async {
    calendars.allows = false;
    await put(tester);
    await go(tester, ['提醒定期扣款與卡費']);
    expect(find.text('沒有取得日曆權限，可以到系統設定開啟'), findsOneWidget);

    calendars
      ..allows = true
      ..choices = [];
    await go(tester, ['提醒定期扣款與卡費']);
    await settle(
      tester,
      () => find.textContaining('手機上沒有可寫入的日曆').evaluate().isNotEmpty,
    );
    expect(find.text('手機上沒有可寫入的日曆，請先在日曆 App 登入 Google 帳號'), findsOneWidget);
    expect(calendar.chosen, isNull);
  });

  testWidgets('a calendar that cannot be read is said so', (tester) async {
    calendars.listFails = true;
    await put(tester);
    await go(tester, ['提醒定期扣款與卡費']);
    await settle(
      tester,
      () => find.textContaining('日曆沒有連上：').evaluate().isNotEmpty,
    );
    expect(find.textContaining('日曆沒有連上：'), findsOneWidget);
  });

  testWidgets('a calendar that cannot be written is said so', (tester) async {
    calendars.writeFails = true;
    await put(tester);
    await go(tester, ['提醒定期扣款與卡費', '工作']);
    await settle(
      tester,
      () => find.textContaining('日曆沒有同步成功').evaluate().isNotEmpty,
    );
    expect(calendar.chosen, (1, '工作'));
    expect(find.text('日曆沒有同步成功'), findsOneWidget);
  });

  testWidgets('a linked calendar\'s details: 寫入金額 off writes the '
      'events without amounts', (tester) async {
    await tester.runAsync(
      () => calendar.choose(
        const CalendarChoice(2, '家庭', ''),
        reminderBookOf(ledger),
      ),
    );
    await put(tester);
    await go(tester, ['已連結 · 寫金額']);
    expect(find.text('同步到「家庭」'), findsOneWidget);
    expect(find.text('例：繳卡費：玉山卡 12,345'), findsOneWidget);
    await go(tester, ['寫入金額']);
    await settle(tester, () => find.text('例：繳卡費：玉山卡').evaluate().isNotEmpty);
    expect(calendar.amounts, isFalse);
    expect(find.text('例：繳卡費：玉山卡'), findsOneWidget);
    final plain = [
      for (final r in reminderBookOf(ledger).reminders()) r.withoutAmount.title,
    ];
    expect([for (final r in calendars.written[2]!) r.title], plain);
  });

  testWidgets('換日曆 moves the reminders to another calendar, clearing '
      'the one before', (tester) async {
    await tester.runAsync(
      () => calendar.choose(
        const CalendarChoice(2, '家庭', ''),
        reminderBookOf(ledger),
      ),
    );
    await put(tester);
    await go(tester, ['已連結', '換日曆']);
    // The one chosen is marked among them.
    expect(find.text('同步到哪個日曆'), findsOneWidget);
    await go(tester, ['工作']);
    await settle(tester, () => calendars.written[1] != null);
    expect(calendar.chosen, (1, '工作'));
    expect(calendars.written[2], isEmpty, reason: 'cleared');
    expect(calendars.written[1], isNotEmpty);
  });

  testWidgets('不再同步, or the card\'s tick, takes the reminders off the '
      'calendar', (tester) async {
    await tester.runAsync(
      () => calendar.choose(
        const CalendarChoice(2, '家庭', ''),
        reminderBookOf(ledger),
      ),
    );
    await put(tester);
    await go(tester, ['已連結', '不再同步']);
    await settle(
      tester,
      () => find.textContaining('已停止同步').evaluate().isNotEmpty,
    );
    expect(calendar.chosen, isNull);
    expect(calendars.written[2], isEmpty);
    expect(find.text('已停止同步，之後的提醒已從日曆移除'), findsOneWidget);
    expect(find.text('提醒定期扣款與卡費'), findsOneWidget);

    await tester.runAsync(
      () => calendar.choose(
        const CalendarChoice(1, '工作', ''),
        reminderBookOf(ledger),
      ),
    );
    await put(tester);
    await go(tester, ['Google 日曆']);
    await settle(tester, () => calendar.chosen == null);
    expect(calendar.chosen, isNull);
  });
}

/// The phone's notifications, as the test sets them, noting what is
/// asked of them.
final class _Phone implements NotifyPort {
  var allows = true;
  var fails = false;
  var testFails = false;
  ReminderStatus allowed = (notifications: true, exact: true, battery: true);
  var asked = 0;
  final tests = <bool>[];
  final opened = <String>[];

  @override
  Future<bool> access() async {
    asked++;
    if (fails) throw StateError('no answer');
    return allows;
  }

  @override
  Future<void> schedule(
    List<Alert> alerts, {
    bool exact = false,
    Set<String>? wanted,
  }) async {}

  @override
  Future<void> test({bool exact = false}) async {
    if (testFails) throw StateError('channel closed');
    tests.add(exact);
  }

  @override
  Future<void> post(Alert alert, int id) async {}

  @override
  Future<ReminderStatus> status() async => allowed;

  @override
  Future<void> openExactSettings() async => opened.add('exact');

  @override
  Future<void> openBatterySettings() async => opened.add('battery');
}

/// The phone's calendars: 工作 and 家庭, keeping what is written to each.
final class _Calendars implements CalendarPort {
  var allows = true;
  var listFails = false;
  var writeFails = false;
  var choices = const [
    CalendarChoice(1, '工作', ''),
    CalendarChoice(2, '家庭', 'me@example.com'),
  ];
  final written = <int, List<Reminder>>{};

  @override
  Future<bool> access() async => allows;

  @override
  Future<List<CalendarChoice>> calendars() async {
    if (listFails) throw const SocketException('calendar provider gone');
    return choices;
  }

  @override
  Future<int> replace(int id, DateTime from, List<Reminder> reminders) async {
    if (writeFails) throw StateError('read only');
    written[id] = reminders;
    return reminders.length;
  }
}
