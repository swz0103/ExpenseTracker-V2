import 'package:flutter/material.dart';

import '../../look/glyphs.dart';
import '../../look/theme.dart';
import '../../look/widgets.dart';
import '../../notifications.dart';
import '../../preferences.dart';

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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHead('外觀與操作'),
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
        ]),
      ],
    );
  }
}

/// 通知: due dates and the daily nudge, and when it comes.
class NotificationsSection extends StatelessWidget {
  const NotificationsSection({super.key, required this.notifier});

  final Notifier notifier;

  /// Turns a kind of notification on, once the phone allows them.
  Future<void> _notify(BuildContext context, {bool? due, bool? nudge}) async {
    final turningOn = (due ?? false) || (nudge ?? false);
    if (turningOn) {
      bool allowed;
      try {
        allowed = await notifier.port.access();
      } on Object {
        allowed = false;
      }
      if (!allowed) {
        if (context.mounted) showNote(context, '沒有取得通知權限，可以到系統設定開啟');
        return;
      }
    }
    notifier.preferences.update(dueAlerts: due, dailyNudge: nudge);
  }

  Future<void> _pickNudgeHour(BuildContext context) async {
    final preferences = notifier.preferences;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: preferences.nudgeHour, minute: 0),
      helpText: '每天幾點提醒（以整點計）',
    );
    if (picked != null) preferences.update(nudgeHour: picked.hour);
  }

  @override
  Widget build(BuildContext context) {
    final preferences = notifier.preferences;
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
              onChanged: (on) => _notify(context, due: on),
            ),
          ),
          MenuRow(
            glyph: Glyph.records,
            title: '每日記帳提醒',
            detail: '當天沒記帳才提醒',
            trailing: Switch(
              value: preferences.dailyNudge,
              onChanged: (on) => _notify(context, nudge: on),
            ),
          ),
          if (preferences.dailyNudge)
            MenuRow(
              glyph: Glyph.calendar,
              title: '提醒時間',
              detail: '每天 ${preferences.nudgeHour}:00',
              onTap: () => _pickNudgeHour(context),
            ),
        ]),
      ],
    );
  }
}
