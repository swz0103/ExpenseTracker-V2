import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../overview/ui/overview_editor.dart';
import '../../../reminders/model/notifications.dart';
import '../../../../core/preferences.dart';

/// 外觀與操作: light or dark, and the small vibrations.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key, required this.preferences});

  final Preferences preferences;

  /// Light, dark, or as the phone is.
  Future<void> _pickAppearance(BuildContext context) async {
    final picked = await showDialog<Appearance>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: Hue.panel,
        title: const Text('外觀'),
        children: [
          for (final a in Appearance.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(a),
              child: Text(
                a.label,
                style: a == preferences.appearance
                    ? const TextStyle(
                        color: Hue.accent,
                        fontWeight: FontWeight.w700,
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
    if (picked != null) preferences.update(appearance: picked);
  }

  /// What the home-screen widget 本月概況 shows.
  Future<void> _pickWidget(BuildContext context) async {
    final picked = await showDialog<WidgetFigures>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: Hue.panel,
        title: const Text('桌面小工具「本月概況」'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('桌面上任何人都看得到。只顯示百分比時，手機裡也只存百分比。', style: mutedSmall),
          ),
          for (final f in WidgetFigures.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(f),
              child: Text(
                f.label,
                style: f == preferences.widgetFigures
                    ? const TextStyle(
                        color: Hue.accent,
                        fontWeight: FontWeight.w700,
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
    if (picked != null) preferences.update(widgetFigures: picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MenuPanel([
          MenuRow(
            glyph: Glyph.moon,
            title: '外觀',
            detail: preferences.appearance.label,
            onTap: () => _pickAppearance(context),
          ),
          MenuRow(
            glyph: Glyph.vibrate,
            title: '震動',
            detail: '點選與存檔時輕震',
            trailing: Switch(
              value: preferences.haptics,
              onChanged: (on) => preferences.update(haptics: on),
            ),
          ),
          MenuRow(
            glyph: Glyph.budget,
            title: '桌面小工具',
            detail: preferences.widgetFigures.label,
            onTap: () => _pickWidget(context),
          ),
          MenuRow(
            glyph: Glyph.overview,
            title: '總覽區塊',
            detail: '排序、隱藏',
            onTap: () => editOverview(context, preferences),
          ),
        ]),
      ],
    );
  }
}

/// 通知: due dates and the daily nudge, when it comes, on the minute or
/// not, a test, and what the phone allows.
class NotificationsSection extends StatefulWidget {
  const NotificationsSection({super.key, required this.notifier});

  final Notifier notifier;

  @override
  State<NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<NotificationsSection>
    with WidgetsBindingObserver {
  Notifier get _notifier => widget.notifier;

  /// What the phone allows, read again when back from its settings.
  ReminderStatus? _status;

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
    try {
      final status = await _notifier.port.status();
      if (mounted) setState(() => _status = status);
    } on Object {
      // A phone that cannot say shows no status.
    }
  }

  /// Turns a kind of notification on, once the phone allows them.
  Future<void> _notify({bool? due, bool? nudge}) async {
    final turningOn = (due ?? false) || (nudge ?? false);
    if (turningOn) {
      bool allowed;
      try {
        allowed = await _notifier.port.access();
      } on Object {
        allowed = false;
      }
      if (!allowed) {
        if (mounted) showNote(context, '沒有取得通知權限，可以到系統設定開啟');
        return;
      }
    }
    _notifier.preferences.update(dueAlerts: due, dailyNudge: nudge);
    unawaited(_readStatus());
  }

  /// Asks again to post notifications; turned off in the system
  /// settings, only the person can turn them back on there.
  Future<void> _askAccess() async {
    bool allowed;
    try {
      allowed = await _notifier.port.access();
    } on Object {
      allowed = false;
    }
    if (!allowed && mounted) showNote(context, '請到系統設定開啟記帳本的通知');
    await _readStatus();
  }

  Future<void> _pickNudgeTime() async {
    final preferences = _notifier.preferences;
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
  Future<void> _exact(bool on) async {
    _notifier.preferences.update(exactReminders: on);
    if (on && _status?.exact == false) {
      showNote(context, '請在接下來的畫面允許「鬧鐘與提醒」');
      await _notifier.port.openExactSettings();
    }
  }

  Future<void> _test() async {
    try {
      await _notifier.port.test(exact: _notifier.preferences.exactReminders);
      if (mounted) showNote(context, '一分鐘後會跳出一則測試通知');
    } on Object catch (error) {
      if (mounted) showNote(context, '無法傳送測試通知：$error');
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final preferences = _notifier.preferences;
    final status = _status;
    final asked = preferences.dueAlerts || preferences.dailyNudge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHead('通知'),
        MenuPanel([
          MenuRow(
            glyph: Glyph.bell,
            title: '到期提醒',
            detail: '定期扣款、卡費',
            trailing: Switch(
              value: preferences.dueAlerts,
              onChanged: (on) => _notify(due: on),
            ),
          ),
          MenuRow(
            glyph: Glyph.records,
            title: '每日記帳提醒',
            detail: '當天沒記帳才提醒',
            trailing: Switch(
              value: preferences.dailyNudge,
              onChanged: (on) => _notify(nudge: on),
            ),
          ),
          if (preferences.dailyNudge)
            MenuRow(
              glyph: Glyph.calendar,
              title: '提醒時間',
              detail:
                  '每天 ${preferences.nudgeHour}:${_two(preferences.nudgeMinute)}',
              onTap: _pickNudgeTime,
            ),
          if (asked)
            MenuRow(
              glyph: Glyph.bolt,
              title: '準時提醒',
              detail: '不讓手機延後，需要允許鬧鐘',
              trailing: Switch(
                value: preferences.exactReminders,
                onChanged: _exact,
              ),
            ),
          if (asked)
            MenuRow(
              glyph: Glyph.chat,
              title: '傳送測試通知',
              detail: '一分鐘後跳出',
              onTap: _test,
            ),
        ]),
        if (asked && status != null) ...[
          const SectionHead('手機設定'),
          MenuPanel([
            MenuRow(
              glyph: Glyph.bell,
              title: '通知權限',
              detail: status.notifications ? '已允許' : '未允許，點一下開啟',
              color: status.notifications ? Hue.ink : Hue.danger,
              onTap: status.notifications ? null : _askAccess,
            ),
            if (preferences.exactReminders)
              MenuRow(
                glyph: Glyph.bolt,
                title: '鬧鐘與提醒',
                detail: status.exact ? '已允許' : '未允許，點一下開啟',
                color: status.exact ? Hue.ink : Hue.danger,
                onTap: status.exact ? null : _notifier.port.openExactSettings,
              ),
            MenuRow(
              glyph: Glyph.shield,
              title: '電池最佳化',
              detail: status.battery ? '不限制' : '可能延後提醒，點一下調整',
              onTap: status.battery ? null : _notifier.port.openBatterySettings,
            ),
          ]),
        ],
      ],
    );
  }
}
