import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../book/keeper.dart';
import '../calendar_sync.dart';
import '../demo/seed.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/exchange.dart';
import '../model/ledger.dart';
import '../notifications.dart';
import '../perf.dart';
import '../preferences.dart';
import '../problems.dart';
import '../screen_privacy.dart';
import '../services.dart';
import 'dialogs.dart';
import 'import_sheet.dart';
import 'nav.dart';
import 'recovery_code.dart';
import 'trash_sheet.dart';

/// 設定與資料: preferences, exporting a month or the whole book, the
/// encrypted ledger's backups and keys, and resetting the demo.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.ledger,
    required this.nav,
    this.services = const Services(),
  });

  final Ledger ledger;
  final Nav nav;

  /// Keys, backups, the calendar and screen hiding; none in the preview.
  final Services services;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late var _month = (widget.ledger.today.year, widget.ledger.today.month);

  Future<void> _copy(String text, String note) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showNote(context, note);
  }

  /// Saves [text] as the file [name] when the ledger can, else copies it.
  Future<void> _save(String name, String text, String what) async {
    final keeper = widget.services.keeper;
    if (keeper == null) return _copy(text, '已複製$what');
    try {
      final saved = await keeper.exportFile(name, text);
      if (mounted && saved) showNote(context, '已下載$what');
    } on Object catch (error) {
      if (mounted) showNote(context, '下載失敗：${describeProblem(error)}');
    }
  }

  /// Saves a backup outside the app. Without a password, only a recovery
  /// code opens it on another phone, so a new one is made and shown.
  Future<void> _export(Keeper keeper) async {
    try {
      // A ledger without a password restores with its recovery code: one
      // is made the first time, and kept after that.
      final code = keeper.hasPassword || keeper.recoveryGiven
          ? null
          : await keeper.newRecoveryCode();
      final saved = await keeper.exportBackup();
      if (!mounted) return;
      if (code != null) {
        // The code changed even if the save was cancelled: show it anyway.
        await showRecoveryCode(
          context,
          code,
          why: saved
              ? '在新手機還原這份備份時，要輸入這組救援碼。請抄下來放在安全的地方，它只會顯示這一次。'
              : '救援碼已更新，之前的不再適用。請抄下來放在安全的地方，它只會顯示這一次。',
        );
      } else if (saved) {
        showNote(
          context,
          keeper.hasPassword ? '已匯出備份檔' : '已匯出備份檔，還原時輸入你抄下的救援碼',
        );
      }
    } on Object catch (error) {
      if (mounted) showNote(context, '匯出失敗：${describeProblem(error)}');
    }
  }

  Future<void> _changePassword(Keeper keeper) async {
    final first = !keeper.hasPassword;
    final passwords = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _PasswordDialog(first: first),
    );
    if (passwords == null) return;
    final (current, next) = passwords;
    try {
      if (first) {
        await keeper.setPassword(next);
        // A ledger started without a password has had no code to show yet.
        final code = await keeper.newRecoveryCode();
        if (mounted) {
          await showRecoveryCode(
            context,
            code,
            why: '密碼設好了。忘記密碼時，只有這組救援碼能打開帳本。請抄下來放在安全的地方，它只會顯示這一次。',
          );
        }
      } else {
        await keeper.changePassword(current, next);
      }
      if (mounted) setState(() {});
      if (mounted) showNote(context, first ? '已設定密碼' : '密碼已變更');
    } on Object catch (error) {
      if (!mounted) return;
      final wrong = '$error'.contains('wrongSecret');
      final weak = '$error'.contains('weakPassword');
      showNote(
        context,
        wrong
            ? '目前的密碼不正確'
            : weak
            ? '新密碼至少要 6 個字'
            : '無法變更密碼（$error）',
      );
    }
  }

  Future<void> _newRecovery(Keeper keeper) async {
    final ok = await confirm(context, '換一組新的救援碼？舊的會立刻失效。', '更換');
    if (!ok) return;
    try {
      final code = await keeper.newRecoveryCode();
      if (mounted) await showRecoveryCode(context, code);
    } on Object catch (error) {
      if (mounted) showNote(context, '沒有換成：${describeProblem(error)}');
    }
  }

  /// Turns screen hiding on or off.
  Future<void> _hideScreen(ScreenPrivacy privacy, bool on) async {
    try {
      await privacy.turn(on: on);
    } on Object {
      if (mounted) showNote(context, '這支手機無法切換截圖設定');
    }
    if (mounted) setState(() {});
  }

  /// Links a calendar, such as Google Calendar, for the due dates, or
  /// changes or stops it.
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
      final picked = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          backgroundColor: Hue.panel,
          title: const Text('同步到哪個日曆'),
          children: [
            for (final c in choices)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(c.id),
                child: Text(
                  '${c.id == chosen ? '✓ ' : ''}${c.name}'
                  '${c.account.isEmpty ? '' : '\n${c.account}'}',
                ),
              ),
            if (chosen != null)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(-1),
                child: const Text('不再同步', style: TextStyle(color: Hue.danger)),
              ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      if (picked == -1) {
        await calendar.forget(widget.ledger);
        if (mounted) showNote(context, '已停止同步，之後的提醒已從日曆移除');
        setState(() {});
        return;
      }
      await calendar.choose(
        choices.firstWhere((c) => c.id == picked),
        widget.ledger,
      );
      final written = await calendar.sync(widget.ledger);
      if (!mounted) return;
      setState(() {});
      showNote(context, written == null ? '日曆沒有同步成功' : '已把 $written 個到期提醒放進日曆');
    } on Object catch (error) {
      if (mounted) showNote(context, '日曆沒有連上：${describeProblem(error)}');
    }
  }

  /// Light, dark, or as the phone is.
  Future<void> _pickAppearance(Preferences preferences) async {
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
                '${a == preferences.appearance ? '✓ ' : '　 '}${a.label}',
              ),
            ),
        ],
      ),
    );
    if (picked != null) preferences.update(appearance: picked);
  }

  /// Turns a kind of notification on, once the phone allows them.
  Future<void> _notify(
    Notifier notifier, {
    bool? due,
    bool? nudge,
  }) async {
    final turningOn = (due ?? false) || (nudge ?? false);
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
    notifier.preferences.update(dueAlerts: due, dailyNudge: nudge);
  }

  Future<void> _pickNudgeHour(Preferences preferences) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: preferences.nudgeHour, minute: 0),
      helpText: '每天幾點提醒（以整點計）',
    );
    if (picked != null) preferences.update(nudgeHour: picked.hour);
  }

  Future<void> _reset() async {
    final ok = await confirm(context, '重設範例資料？目前的變更會清除。', '重設', danger: true);
    if (!ok) return;
    widget.ledger.resetTo(demoLedger());
    if (mounted) showNote(context, '已重設範例資料');
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final preferences = widget.services.preferences;
    final notifier = widget.services.notifier;
    return ListenableBuilder(
      listenable: Listenable.merge([ledger, ?preferences]),
      builder: (context, _) {
        final (year, month) = _month;
        final entries = ledger.entriesIn(year, month);
        final keeper = widget.services.keeper;
        final privacy = widget.services.privacy;
        final calendar = widget.services.calendar;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            // A long press on the title shows the timings and background
            // faults, for looking into a problem.
            GestureDetector(
              onLongPress: _showPerformance,
              child: PageHeader('設定與資料', onBack: widget.nav.back),
            ),
            const SectionHead('紀錄'),
            _Panel([
              _Item(
                glyph: Glyph.calendar,
                title: '匯出月份',
                trailing: MonthSwitch(
                  month: _month,
                  latest: (ledger.today.year, ledger.today.month),
                  onChanged: (m) => setState(() => _month = m),
                ),
              ),
              _Item(
                glyph: Glyph.download,
                title: '匯出 $month 月',
                detail: '${entries.length} 筆 · CSV',
                onTap: () => _save(
                  '記帳本-$year-${'$month'.padLeft(2, '0')}.csv',
                  toCsv(ledger, entries),
                  ' ${entries.length} 筆紀錄的 CSV',
                ),
              ),
              _Item(
                glyph: Glyph.records,
                title: '匯出全部',
                detail: '${ledger.entries.length} 筆 · CSV',
                onTap: () => _save(
                  '記帳本-全部.csv',
                  toCsv(ledger, ledger.entries),
                  ' ${ledger.entries.length} 筆紀錄的 CSV',
                ),
              ),
              _Item(
                glyph: Glyph.add,
                title: '匯入 CSV',
                detail: '選檔案或貼上',
                onTap: () =>
                    importInto(context, ledger, readFile: keeper?.readFile),
              ),
              _Item(
                glyph: Glyph.scan,
                title: '匯入電子發票',
                detail: '載具消費明細',
                onTap: () => importInto(
                  context,
                  ledger,
                  invoices: true,
                  readFile: keeper?.readFile,
                ),
              ),
              _Item(
                glyph: Glyph.reset,
                title: '最近刪除',
                detail: ledger.trash.isEmpty
                    ? '沒有'
                    : '${ledger.trash.length} 筆可放回',
                onTap: () => showTrash(context, ledger),
              ),
            ]),
            if (preferences != null) ...[
              const SectionHead('外觀與操作'),
              _Panel([
                _Item(
                  glyph: Glyph.moon,
                  title: '外觀',
                  detail: preferences.appearance.label,
                  onTap: () => _pickAppearance(preferences),
                ),
                _Item(
                  glyph: Glyph.vibrate,
                  title: '震動回饋',
                  detail: '點選與存檔時輕震',
                  trailing: Switch(
                    value: preferences.haptics,
                    onChanged: (on) => preferences.update(haptics: on),
                  ),
                ),
              ]),
            ],
            if (notifier != null) ...[
              const SectionHead('通知'),
              _Panel([
                _Item(
                  glyph: Glyph.bell,
                  title: '到期提醒',
                  detail: '定期扣款、卡費',
                  trailing: Switch(
                    value: notifier.preferences.dueAlerts,
                    onChanged: (on) => _notify(notifier, due: on),
                  ),
                ),
                _Item(
                  glyph: Glyph.records,
                  title: '每日記帳提醒',
                  detail: '當天沒記帳才提醒',
                  trailing: Switch(
                    value: notifier.preferences.dailyNudge,
                    onChanged: (on) => _notify(notifier, nudge: on),
                  ),
                ),
                if (notifier.preferences.dailyNudge)
                  _Item(
                    glyph: Glyph.calendar,
                    title: '提醒時間',
                    detail: '每天 ${notifier.preferences.nudgeHour}:00',
                    onTap: () => _pickNudgeHour(notifier.preferences),
                  ),
              ]),
            ],
            if (keeper != null || privacy != null) ...[
              const SectionHead('安全'),
              _Panel([
                if (keeper != null) ...[
                  _Item(
                    glyph: Glyph.safe,
                    title: '備份帳本',
                    detail: '存到下載或雲端硬碟',
                    onTap: () => _export(keeper),
                  ),
                  _Item(
                    glyph: Glyph.shield,
                    title: keeper.hasPassword ? '變更密碼' : '設定密碼',
                    detail: keeper.hasPassword ? '已設定' : '目前不用密碼',
                    onTap: () => _changePassword(keeper),
                  ),
                  _Item(
                    glyph: Glyph.ticket,
                    title: keeper.hasPassword ? '更換救援碼' : '取得救援碼',
                    detail: '換手機還原用',
                    onTap: () => _newRecovery(keeper),
                  ),
                ],
                if (privacy != null)
                  _Item(
                    glyph: Glyph.eyeOff,
                    title: '不讓截圖',
                    detail: '最近使用的 App 也看不到',
                    trailing: Switch(
                      value: privacy.on,
                      onChanged: (on) => _hideScreen(privacy, on),
                    ),
                  ),
                if (keeper != null && keeper.hasPassword)
                  _Item(
                    glyph: Glyph.close,
                    title: '鎖定帳本',
                    detail: '回到解鎖畫面',
                    onTap: keeper.lock,
                  ),
              ]),
            ],
            if (calendar != null) ...[
              const SectionHead('連結'),
              _Panel([
                _Item(
                  glyph: Glyph.calendar,
                  title: 'Google 日曆',
                  detail: switch (calendar.chosen) {
                    (_, final name)? => '同步到「$name」',
                    null => '提醒定期扣款與卡費',
                  },
                  onTap: () => _linkCalendar(calendar),
                ),
              ]),
            ],
            // Only the preview's made-up book can be reset.
            if (ledger.journal == null) ...[
              const SizedBox(height: 16),
              _Panel([
                _Item(
                  glyph: Glyph.reset,
                  title: '重設範例資料',
                  color: Hue.danger,
                  onTap: _reset,
                ),
              ]),
            ],
          ],
        );
      },
    );
  }

  /// Load and frame timings with the background faults, in a sheet.
  void _showPerformance() {
    showSheet<void>(
      context,
      (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '效能與診斷',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final (name, figure) in Perf.instance.report)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text(name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        figure,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 13, color: Hue.muted),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A white panel of rows with thin rules between them.
class _Panel extends StatelessWidget {
  const _Panel(this.items);

  final List<Widget> items;

  @override
  Widget build(BuildContext context) => SoftPanel(
    color: Hue.white,
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      children: [
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const Divider(height: 1, indent: 56, endIndent: 14),
          item,
        ],
      ],
    ),
  );
}

/// One setting: an icon, its name, a few words on its state, and what a
/// tap does, or a control of its own at the end.
class _Item extends StatelessWidget {
  const _Item({
    required this.glyph,
    required this.title,
    this.detail,
    this.onTap,
    this.trailing,
    this.color = Hue.ink,
  });

  final Glyph glyph;
  final String title;
  final String? detail;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Hue.tile,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: GlyphIcon(
                  glyph,
                  size: 18,
                  color: color == Hue.ink ? Hue.accent : color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 15, color: color),
                ),
              ),
              if (detail != null)
                Flexible(
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 13, color: Hue.muted),
                  ),
                ),
              ?trailing,
              if (trailing == null && onTap != null) ...[
                const SizedBox(width: 4),
                const GlyphIcon(Glyph.next, size: 16, color: Hue.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the current password and a new one twice; returns the
/// current and the new one.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.first});

  /// Setting a password on a ledger that has none: nothing to confirm.
  final bool first;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  void _submit() {
    if (_next.text != _again.text) {
      setState(() => _problem = '兩次輸入的新密碼不一樣');
      return;
    }
    Navigator.of(context).pop((_current.text, _next.text));
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController controller, String hint) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        obscureText: true,
        decoration: InputDecoration(hintText: hint),
      ),
    );
    final first = widget.first;
    return AlertDialog(
      title: Text(first ? '設定密碼' : '變更密碼'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!first) field(_current, '目前的密碼'),
          field(_next, '新密碼'),
          field(_again, '再輸入一次新密碼'),
          if (_problem case final problem?)
            Text(problem, style: const TextStyle(color: Hue.danger)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(first ? '設定' : '變更')),
      ],
    );
  }
}
