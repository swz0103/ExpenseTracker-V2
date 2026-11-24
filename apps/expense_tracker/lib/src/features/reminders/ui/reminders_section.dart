import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ledger/ledger.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/messages/problem_messages.dart';
import '../model/calendar_sync.dart';
import '../model/reminder_alerts.dart';
import '../model/reminder_rules.dart';
import '../model/reminders.dart';
import '../../../core/messages/reminder_messages.dart';
import '../../../core/platform/preferences.dart';
import '../../../core/design_system/settings_colors.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/formatting/words.dart';
import '../../../../design_system/display/status_messages.dart';
import '../../../core/diagnostics/error_steps.dart';

part 'reminders_phone.dart';

/// 通知與提醒: four cards (到期提醒, 預算提醒, 每日記帳, Google 日曆), the
/// tick on each turning it on or off and a tap opening its details in the
/// middle of the screen; under them, one strip on what the phone allows.
class RemindersSection extends StatefulWidget {
  const RemindersSection({
    super.key,
    required this.ledger,
    this.notifier,
    this.calendar,
    this.onBudgets,
  });

  final Ledger ledger;
  final Notifier? notifier;
  final CalendarSync? calendar;

  /// Opens 預算管理, where each budget's warning is set.
  final VoidCallback? onBudgets;

  @override
  State<RemindersSection> createState() => _RemindersSectionState();
}

class _RemindersSectionState extends State<RemindersSection>
    with WidgetsBindingObserver, _CalendarActions {
  /// What the phone allows, read again when back from its settings.
  ReminderStatus? _status;

  Ledger get _ledger => widget.ledger;

  @override
  ReminderBook get _book => reminderBookOf(_ledger);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _readStatus();
  }

  Future<void> _readStatus() async {
    final notifier = widget.notifier;
    if (notifier == null) return;
    try {
      final status = await notifier.port.status();
      if (mounted) setState(() => _status = status);
    } on Object catch (error, stack) {
      // A phone that cannot say shows no status.
      ErrorLog.instance.record(ErrorSteps.notificationStatus, error, stack);
    }
  }

  /// Turns a kind of notification on, once the phone allows them.
  Future<void> _notify(
    Notifier notifier, {
    bool? due,
    bool? nudge,
    bool? budget,
  }) async {
    final turningOn = (due ?? false) || (nudge ?? false) || (budget ?? false);
    if (turningOn) {
      bool allowed;
      try {
        allowed = await notifier.port.access();
      } on Object catch (error) {
        ErrorLog.instance.record('通知權限', error);
        allowed = false;
      }
      if (!allowed) {
        if (mounted) showNote(context, '沒有取得通知權限，可以到系統設定開啟');
        return;
      }
    }
    notifier.preferences.update(
      dueAlerts: due,
      dailyNudge: nudge,
      budgetAlerts: budget,
    );
    unawaited(_readStatus());
  }

  /// Asks again to post notifications; turned off in the system
  /// settings, only the person can turn them back on there.
  Future<void> _askAccess(Notifier notifier) async {
    bool allowed;
    try {
      allowed = await notifier.port.access();
    } on Object catch (error) {
      ErrorLog.instance.record('通知權限', error);
      allowed = false;
    }
    // Exception to glossary: a switch in the system settings, which is turned on (開啟).
    if (!allowed && mounted) showNote(context, '請到系統設定開啟記帳本的通知');
    await _readStatus();
  }

  Future<void> _pickNudgeTime(Notifier notifier) async {
    final preferences = notifier.preferences;
    final picked = await pickTime(
      context,
      initial: TimeOfDay(
        hour: preferences.nudgeHour,
        minute: preferences.nudgeMinute,
      ),
      title: '每天幾點提醒',
      color: SettingsColors.daily,
    );
    if (picked != null) {
      preferences.update(nudgeHour: picked.hour, nudgeMinute: picked.minute);
    }
  }

  /// Reminders on the minute need the phone's permission for alarms,
  /// given in its settings.
  Future<void> _exact(Notifier notifier, bool on) async {
    notifier.preferences.update(exactReminders: on);
    if (on && _status?.exact == false) {
      showNote(context, '請在接下來的畫面允許「鬧鐘與提醒」');
      await notifier.port.openExactSettings();
    }
  }

  Future<void> _test(Notifier notifier) async {
    try {
      await notifier.port.test(exact: notifier.preferences.exactReminders);
      if (mounted) showNote(context, '一分鐘後會跳出一則測試通知');
    } on Object catch (error) {
      ErrorLog.instance.record('測試通知', error);
      if (mounted) showNote(context, '無法傳送測試通知：${ErrorLog.describe(error)}');
    }
  }

  /// Whether a kind of notification the person turned on can come: shown
  /// on only while the phone allows notifications as well, so a card
  /// never says on while nothing would be posted.
  bool _shownOn(bool asked) => asked && _status?.notifications != false;

  /// 去開 for the battery: the app's own page of the system settings, and
  /// what to choose there.
  Future<void> _battery(Notifier notifier) async {
    try {
      await notifier.port.openBatterySettings();
    } on Object catch (error) {
      ErrorLog.instance.record(ErrorSteps.notificationStatus, error);
    }
    if (mounted) showNote(context, ReminderMessages.batteryHow);
  }

  /// What the daily nudge's time can be trusted to: on the minute when
  /// asked for and allowed, else as late as the phone may post it.
  String _nudgeTiming(Preferences preferences) =>
      preferences.exactReminders && _status?.exact != false
      ? ' · 準時'
      : ' · ${ReminderMessages.lateBy(ReminderTiming.inexactLateness)}';

  // The details of each card.

  void _dueDetails(Notifier notifier) {
    final preferences = notifier.preferences;
    showCenterPanel(
      context,
      glyph: Glyph.bell,
      color: SettingsColors.reminders,
      title: '到期提醒',
      detail: '定期扣款、卡費',
      value: () => _shownOn(preferences.dueAlerts),
      onChanged: (on) => _notify(notifier, due: on),
      body: (context) {
        final coming = reminderBookOf(_ledger).reminders().take(4).toList();
        return _Labelled(
          '接下來會提醒',
          coming.isEmpty
              ? Text(
                  ReminderMessages.nothingDueWithin(ReminderTiming.horizonDays),
                  style: mutedSmall,
                )
              : CardGrid([
                  for (final r in coming)
                    _Chip(
                      color: SettingsColors.reminders,
                      top: formatMd(r.day),
                      bottom: r.title,
                    ),
                ], gap: 10),
        );
      },
    );
  }

  void _budgetDetails(Notifier notifier) {
    final preferences = notifier.preferences;
    final onBudgets = widget.onBudgets;
    showCenterPanel(
      context,
      glyph: Glyph.pie,
      color: SettingsColors.budget,
      title: '預算提醒',
      detail: '用到警示比例、${StatusWords.over}時',
      value: () => _shownOn(preferences.budgetAlerts),
      onChanged: (on) => _notify(notifier, budget: on),
      body: (context) {
        final budgets = _ledger.budgets.all.where((b) => b.limit > 0).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Labelled(
              '現在的設定',
              budgets.isEmpty
                  ? const Text('還沒有設定預算', style: mutedSmall)
                  : CardGrid([
                      for (final b in budgets.take(4))
                        _Chip(
                          color: SettingsColors.budget,
                          top: '用到',
                          bottom:
                              '${b.category == allSpending ? '總預算' : b.category} ${b.warning}%',
                        ),
                    ], gap: 10),
            ),
            if (onBudgets != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: TextButton.icon(
                  style: wordButton(
                    deepOf(SettingsColors.budget),
                    minimumSize: Size(0, 48),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onBudgets();
                  },
                  icon: const GlyphIcon(Glyph.pie, size: 18),
                  label: const Text(
                    '到預算管理改比例 ›',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _dailyDetails(Notifier notifier) {
    final preferences = notifier.preferences;
    const color = SettingsColors.daily;
    showCenterPanel(
      context,
      glyph: Glyph.calendar,
      color: color,
      title: '每日記帳',
      detail: '當天沒記帳才提醒',
      value: () => _shownOn(preferences.dailyNudge),
      onChanged: (on) => _notify(notifier, nudge: on),
      body: (context) => ListenableBuilder(
        listenable: preferences,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColorCard(
              color: color,
              amount: 0.16,
              radius: Radii.large,
              // The time too, not only what it is for.
              label:
                  '提醒時間：${formatHm(preferences.nudgeHour, preferences.nudgeMinute)}',
              onTap: () => _pickNudgeTime(notifier),
              padding: const EdgeInsets.symmetric(vertical: Space.s4),
              child: Center(
                child: Text(
                  formatHmSpaced(
                    preferences.nudgeHour,
                    preferences.nudgeMinute,
                  ),
                  style: TextStyle(
                    fontSize: TextSize.hero,
                    fontWeight: FontWeight.w800,
                    color: deepOf(color),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.s2),
            _ToggleRow(
              color: color,
              title: '準時提醒',
              detail: preferences.exactReminders
                  ? '需要允許鬧鐘'
                  : ReminderMessages.lateWithout(
                      ReminderTiming.inexactLateness,
                    ),
              value: preferences.exactReminders,
              onChanged: (on) => _exact(notifier, on),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifier = widget.notifier;
    final calendar = widget.calendar;
    final preferences = notifier?.preferences;
    final status = _status;
    final asked =
        preferences != null &&
        (preferences.dueAlerts ||
            preferences.dailyNudge ||
            preferences.budgetAlerts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardGrid([
          if (notifier != null && preferences != null) ...[
            SettingCard(
              glyph: Glyph.bell,
              color: SettingsColors.reminders,
              title: '到期提醒',
              detail: '信用卡、定期交易',
              value: _shownOn(preferences.dueAlerts),
              onChanged: (on) => _notify(notifier, due: on),
              onTap: () => _dueDetails(notifier),
            ),
            SettingCard(
              glyph: Glyph.pie,
              color: SettingsColors.budget,
              title: '預算提醒',
              detail: '用到幾成時',
              value: _shownOn(preferences.budgetAlerts),
              onChanged: (on) => _notify(notifier, budget: on),
              onTap: () => _budgetDetails(notifier),
            ),
            SettingCard(
              glyph: Glyph.calendar,
              color: SettingsColors.daily,
              title: '每日記帳',
              detail:
                  '每天 ${formatHm(preferences.nudgeHour, preferences.nudgeMinute)}'
                  '${_nudgeTiming(preferences)}',
              value: _shownOn(preferences.dailyNudge),
              onChanged: (on) => _notify(notifier, nudge: on),
              onTap: () => _dailyDetails(notifier),
            ),
          ],
          if (calendar != null)
            SettingCard(
              glyph: Glyph.calendar,
              color: SettingsColors.calendar,
              title: ReminderMessages.calendarTitle,
              detail: calendar.chosen == null
                  ? ReminderMessages.calendarAbout
                  : '已連結${calendar.amounts ? ' · 寫金額' : ''}',
              value: calendar.chosen != null,
              onChanged: (on) =>
                  on ? _linkCalendar(calendar) : _forgetCalendar(calendar),
              onTap: () => calendar.chosen == null
                  ? _linkCalendar(calendar)
                  : _calendarDetails(calendar),
            ),
        ]),
        if (notifier != null && asked && status != null) ...[
          const SizedBox(height: Space.s3),
          _PhoneStrip(
            status: status,
            exact: notifier.preferences.exactReminders,
            onTest: () => _test(notifier),
            onNotifications: () => _askAccess(notifier),
            onExact: notifier.port.openExactSettings,
            onBattery: () => _battery(notifier),
          ),
        ],
      ],
    );
  }
}

/// What falls due in [ledger], as the calendar and the notifications
/// follow it.
ReminderBook reminderBookOf(Ledger ledger) => ReminderBook(
  changes: ledger.watch(reminderTopics),
  clock: () => ledger.today,
  recurring: ledger.recurring,
  recurringService: ledger.recurringService,
  accounts: ledger.accounts,
  statementService: ledger.statementService,
  entries: ledger.entries,
  budgets: ledger.budgets,
  budgetService: ledger.budgetService,
);
