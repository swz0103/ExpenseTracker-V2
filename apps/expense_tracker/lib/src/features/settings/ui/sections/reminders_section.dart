import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/ledger/ledger.dart';
import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/problems.dart';
import '../../../reminders/model/calendar_sync.dart';
import '../../../reminders/model/notifications.dart';
import '../../../reminders/model/reminders.dart';
import '../settings_hue.dart';

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
    with WidgetsBindingObserver {
  /// What the phone allows, read again when back from its settings.
  ReminderStatus? _status;

  Ledger get _ledger => widget.ledger;

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
    } on Object {
      // A phone that cannot say shows no status.
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
      } on Object {
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
    } on Object {
      allowed = false;
    }
    if (!allowed && mounted) showNote(context, '請到系統設定開啟記帳本的通知');
    await _readStatus();
  }

  Future<void> _pickNudgeTime(Notifier notifier) async {
    final preferences = notifier.preferences;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: preferences.nudgeHour,
        minute: preferences.nudgeMinute,
      ),
      helpText: '每天幾點提醒',
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
      if (mounted) showNote(context, '無法傳送測試通知：$error');
    }
  }

  /// Links a calendar for the due dates, or changes it.
  Future<void> _linkCalendar(CalendarSync calendar) async {
    try {
      if (!await calendar.port.access()) {
        if (mounted) showNote(context, '沒有取得日曆權限，可以到系統設定開啟');
        return;
      }
      final choices = await calendar.port.calendars();
      if (!mounted) return;
      if (choices.isEmpty) {
        showNote(context, '手機上沒有可寫入的日曆，請先在日曆 App 登入 Google 帳號');
        return;
      }
      final chosen = calendar.chosen?.$1;
      final picked = await showPanel<int>(
        context,
        (context) => CenterPanel(
          glyph: Glyph.calendar,
          color: SettingsHue.calendar,
          title: '同步到哪個日曆',
          body: Column(
            children: [
              for (final c in choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ColorCard(
                    color: SettingsHue.calendar,
                    amount: c.id == chosen ? 0.32 : 0.14,
                    radius: 16,
                    label: c.name,
                    onTap: () => Navigator.of(context).pop(c.id),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (c.account.isNotEmpty)
                                Text(c.account, style: mutedSmall),
                            ],
                          ),
                        ),
                        if (c.id == chosen)
                          const GlyphIcon(
                            Glyph.check,
                            size: 20,
                            color: SettingsHue.calendar,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            PanelButton('取消', onTap: () => Navigator.of(context).pop()),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      await calendar.choose(choices.firstWhere((c) => c.id == picked), _ledger);
      final written = await calendar.sync(_ledger);
      if (!mounted) return;
      setState(() {});
      showNote(context, written == null ? '日曆沒有同步成功' : '已把 $written 個到期提醒放進日曆');
    } on Object catch (error) {
      if (mounted) showNote(context, '日曆沒有連上：${describeProblem(error)}');
    }
  }

  Future<void> _forgetCalendar(CalendarSync calendar) async {
    await calendar.forget(_ledger);
    if (mounted) showNote(context, '已停止同步，之後的提醒已從日曆移除');
    if (mounted) setState(() {});
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  // The details of each card.

  void _dueDetails(Notifier notifier) {
    final preferences = notifier.preferences;
    showCenterPanel(
      context,
      glyph: Glyph.bell,
      color: SettingsHue.reminders,
      title: '到期提醒',
      detail: '定期扣款、卡費',
      value: () => preferences.dueAlerts,
      onChanged: (on) => _notify(notifier, due: on),
      body: (context) {
        final coming = _ledger.reminders(days: 30).take(4).toList();
        return _Labelled(
          '接下來會提醒',
          coming.isEmpty
              ? const Text('30 天內沒有到期的項目', style: mutedSmall)
              : CardGrid([
                  for (final r in coming)
                    _Chip(
                      color: SettingsHue.reminders,
                      top: '${r.day.month}/${r.day.day}',
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
      color: SettingsHue.budget,
      title: '預算提醒',
      detail: '用到警示比例、超支時',
      value: () => preferences.budgetAlerts,
      onChanged: (on) => _notify(notifier, budget: on),
      body: (context) {
        final budgets = _ledger.budgets.where((b) => b.limit > 0).toList();
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
                          color: SettingsHue.budget,
                          top: '用到',
                          bottom:
                              '${b.category == Ledger.allSpending ? '總預算' : b.category} ${b.warning}%',
                        ),
                    ], gap: 10),
            ),
            if (onBudgets != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: deepOf(SettingsHue.budget),
                    minimumSize: const Size(0, 48),
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
    const color = SettingsHue.daily;
    showCenterPanel(
      context,
      glyph: Glyph.calendar,
      color: color,
      title: '每日記帳',
      detail: '當天沒記帳才提醒',
      value: () => preferences.dailyNudge,
      onChanged: (on) => _notify(notifier, nudge: on),
      body: (context) => ListenableBuilder(
        listenable: preferences,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColorCard(
              color: color,
              amount: 0.16,
              radius: 18,
              label: '提醒時間',
              onTap: () => _pickNudgeTime(notifier),
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  '${_two(preferences.nudgeHour)} : '
                  '${_two(preferences.nudgeMinute)}',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: deepOf(color),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _ToggleRow(
              color: color,
              title: '準時提醒',
              detail: '需要允許鬧鐘',
              value: preferences.exactReminders,
              onChanged: (on) => _exact(notifier, on),
            ),
          ],
        ),
      ),
    );
  }

  void _calendarDetails(CalendarSync calendar) {
    const color = SettingsHue.calendar;
    showCenterPanel(
      context,
      glyph: Glyph.calendar,
      color: color,
      title: 'Google 日曆',
      detail: switch (calendar.chosen) {
        (_, final name)? => '同步到「$name」',
        null => '提醒定期扣款與卡費',
      },
      body: (context) => StatefulBuilder(
        builder: (context, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColorCard(
              color: color,
              amount: 0.16,
              radius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _ToggleRow(
                    color: color,
                    flat: true,
                    title: '寫入金額',
                    detail: calendar.amounts ? '例：繳卡費：玉山卡 12,345' : '例：繳卡費：玉山卡',
                    value: calendar.amounts,
                    onChanged: (on) async {
                      await calendar.setAmounts(on, _ledger);
                      setState(() {});
                    },
                  ),
                  const Divider(height: 1),
                  InkWell(
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _linkCalendar(calendar);
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 52),
                      child: Row(
                        children: [
                          Text(
                            '換日曆',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: deepOf(color),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${calendar.chosen?.$2 ?? ''} ›',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: deepOf(color),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Hue.danger,
                minimumSize: const Size(0, 48),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _forgetCalendar(calendar);
              },
              child: const Text(
                '不再同步',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
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
              color: SettingsHue.reminders,
              title: '到期提醒',
              detail: '信用卡、定期交易',
              value: preferences.dueAlerts,
              onChanged: (on) => _notify(notifier, due: on),
              onTap: () => _dueDetails(notifier),
            ),
            SettingCard(
              glyph: Glyph.pie,
              color: SettingsHue.budget,
              title: '預算提醒',
              detail: '用到幾成時',
              value: preferences.budgetAlerts,
              onChanged: (on) => _notify(notifier, budget: on),
              onTap: () => _budgetDetails(notifier),
            ),
            SettingCard(
              glyph: Glyph.calendar,
              color: SettingsHue.daily,
              title: '每日記帳',
              detail:
                  '每天 ${_two(preferences.nudgeHour)}:'
                  '${_two(preferences.nudgeMinute)}'
                  '${preferences.exactReminders ? ' · 準時' : ''}',
              value: preferences.dailyNudge,
              onChanged: (on) => _notify(notifier, nudge: on),
              onTap: () => _dailyDetails(notifier),
            ),
          ],
          if (calendar != null)
            SettingCard(
              glyph: Glyph.calendar,
              color: SettingsHue.calendar,
              title: 'Google 日曆',
              detail: calendar.chosen == null
                  ? '提醒定期扣款與卡費'
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
          const SizedBox(height: 12),
          _PhoneStrip(
            status: status,
            exact: notifier.preferences.exactReminders,
            onTest: () => _test(notifier),
            onNotifications: () => _askAccess(notifier),
            onExact: notifier.port.openExactSettings,
            onBattery: notifier.port.openBatterySettings,
          ),
        ],
      ],
    );
  }
}

/// The strip under the cards: green with 試一則 when the phone allows
/// everything asked of it, gold naming what is still off with 去開.
class _PhoneStrip extends StatelessWidget {
  const _PhoneStrip({
    required this.status,
    required this.exact,
    required this.onTest,
    required this.onNotifications,
    required this.onExact,
    required this.onBattery,
  });

  final ReminderStatus status;
  final bool exact;
  final VoidCallback onTest;
  final VoidCallback onNotifications;
  final VoidCallback onExact;
  final VoidCallback onBattery;

  @override
  Widget build(BuildContext context) {
    final (String? missing, VoidCallback? fix) = !status.notifications
        ? ('通知權限沒開', onNotifications)
        : exact && !status.exact
        ? ('鬧鐘與提醒沒開', onExact)
        : !status.battery
        ? ('電池最佳化可能延後提醒', onBattery)
        : (null, null);
    final good = missing == null;
    final color = good ? Hue.positive : SettingsHue.warning;
    return ColorCard(
      color: color,
      amount: 0.16,
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
      child: Row(
        children: [
          GlyphIcon(
            good ? Glyph.check : Glyph.info,
            size: 20,
            color: deepOf(color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OneLine(
              missing ?? '手機設定都好了',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: deepOf(color),
              ),
            ),
          ),
          FilledButton(
            onPressed: good ? onTest : fix,
            style: FilledButton.styleFrom(
              backgroundColor: deepOf(color),
              foregroundColor: Hue.paper,
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              good ? '試一則' : '去開',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small label over what it names, inside a panel.
class _Labelled extends StatelessWidget {
  const _Labelled(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Hue.muted,
        ),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );
}

/// A tinted block with a small line over a bold one: 11/15 over 健身房
/// 1,680.
class _Chip extends StatelessWidget {
  const _Chip({required this.color, required this.top, required this.bottom});

  final Color color;
  final String top;
  final String bottom;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
    decoration: BoxDecoration(
      color: tintOf(color, 0.16),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OneLine(
          top,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: deepOf(color),
          ),
        ),
        OneLine(
          bottom,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: deepOf(color),
          ),
        ),
      ],
    ),
  );
}

/// A row with a name and a line under it on the left and a [TickSwitch]
/// on the right; a tinted block of its own unless [flat].
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.color,
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
    this.flat = false,
  });

  final Color color;
  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: 10, horizontal: flat ? 0 : 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: deepOf(color),
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(fontSize: 13, color: deepOf(color)),
                ),
              ],
            ),
          ),
          TickSwitch(
            value: value,
            color: color,
            label: title,
            onChanged: onChanged,
          ),
        ],
      ),
    );
    final whole = ToggleRow(
      value: value,
      onChanged: onChanged,
      label: title,
      radius: flat ? 0 : 18,
      child: row,
    );
    if (flat) return whole;
    return Container(
      decoration: BoxDecoration(
        color: tintOf(color, 0.16),
        borderRadius: BorderRadius.circular(18),
      ),
      child: whole,
    );
  }
}
