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
import '../perf.dart';
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

  Future<void> _reset() async {
    final ok = await confirm(context, '重設範例資料？目前的變更會清除。', '重設', danger: true);
    if (!ok) return;
    widget.ledger.resetTo(demoLedger());
    if (mounted) showNote(context, '已重設範例資料');
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final (year, month) = _month;
        final entries = ledger.entriesIn(year, month);
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 32),
          children: [
            PageHeader('設定與資料', onBack: widget.nav.back),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHead('匯出帳本'),
                  SoftPanel(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text(
                              '選擇月份',
                              style: TextStyle(fontSize: 13, color: Hue.muted),
                            ),
                            const Spacer(),
                            MonthSwitch(
                              month: _month,
                              latest: (ledger.today.year, ledger.today.month),
                              onChanged: (m) => setState(() => _month = m),
                            ),
                          ],
                        ),
                        const Divider(),
                        _Export(
                          badge: 'CSV',
                          title: '下載收支紀錄',
                          detail: '$year 年 $month 月 · ${entries.length} 筆紀錄',
                          onTap: () => _save(
                            '記帳本-$year-${'$month'.padLeft(2, '0')}.csv',
                            toCsv(ledger, entries),
                            ' ${entries.length} 筆紀錄的 CSV',
                          ),
                        ),
                        const Divider(),
                        _Export(
                          badge: 'CSV',
                          title: '下載全部紀錄',
                          detail: '所有月份 · ${ledger.entries.length} 筆紀錄',
                          onTap: () => _save(
                            '記帳本-全部.csv',
                            toCsv(ledger, ledger.entries),
                            ' ${ledger.entries.length} 筆紀錄的 CSV',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SectionHead('匯入紀錄'),
                  SoftPanel(
                    child: Column(
                      children: [
                        _Export(
                          badge: 'CSV',
                          title: '從 CSV 匯入',
                          detail: '選檔案或貼上；本 App 下載的紀錄可以完整匯回',
                          icon: Glyph.add,
                          onTap: () => importInto(
                            context,
                            ledger,
                            readFile: widget.services.keeper?.readFile,
                          ),
                        ),
                        const Divider(),
                        _Export(
                          badge: '發票',
                          title: '匯入電子發票',
                          detail: '貼上財政部載具消費明細，自動帶入商家與分類',
                          icon: Glyph.add,
                          onTap: () => importInto(
                            context,
                            ledger,
                            invoices: true,
                            readFile: widget.services.keeper?.readFile,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SectionHead('最近刪除'),
                  SoftPanel(
                    child: _Export(
                      badge: '刪除',
                      title: '最近刪除',
                      detail: ledger.trash.isEmpty
                          ? '30 天內沒有刪除的紀錄'
                          : '${ledger.trash.length} 筆，30 天內可以放回',
                      icon: Glyph.reset,
                      onTap: () => showTrash(context, ledger),
                    ),
                  ),
                  if (widget.services.keeper case final keeper?) ...[
                    const SectionHead('帳本安全'),
                    SoftPanel(
                      child: Column(
                        children: [
                          _Export(
                            badge: '備份',
                            title: '備份帳本',
                            detail: '每週會自動備份；這裡另存一份到下載或雲端硬碟，換手機時用來還原',
                            icon: Glyph.download,
                            onTap: () => _export(keeper),
                          ),
                          const Divider(),
                          _Export(
                            badge: '密碼',
                            title: keeper.hasPassword ? '變更密碼' : '設定密碼',
                            detail: keeper.hasPassword
                                ? '至少 6 個字'
                                : '目前打開 App 不用密碼；設定後每次都要輸入',
                            icon: Glyph.edit,
                            onTap: () => _changePassword(keeper),
                          ),
                          const Divider(),
                          _Export(
                            badge: '救援',
                            title: keeper.hasPassword ? '更換救援碼' : '取得救援碼',
                            detail: keeper.hasPassword
                                ? '舊的救援碼會失效'
                                : '沒有密碼時，換手機要靠它還原備份',
                            icon: Glyph.reset,
                            onTap: () => _newRecovery(keeper),
                          ),
                          if (keeper.hasPassword) ...[
                            const Divider(),
                            _Export(
                              badge: '鎖定',
                              title: '鎖定帳本',
                              detail: '回到輸入密碼的畫面',
                              icon: Glyph.next,
                              onTap: keeper.lock,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (widget.services.privacy case final privacy?) ...[
                    const SectionHead('螢幕隱私'),
                    SoftPanel(
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('不讓截圖', style: TextStyle(fontSize: 14)),
                                SizedBox(height: 2),
                                Text(
                                  '也不在最近使用的 App 裡顯示畫面',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Hue.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: privacy.on,
                            onChanged: (on) => _hideScreen(privacy, on),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (widget.services.calendar case final calendar?) ...[
                    const SectionHead('Google 日曆'),
                    SoftPanel(
                      child: _Export(
                        badge: '日曆',
                        title: switch (calendar.chosen) {
                          (_, final name)? => '同步到「$name」',
                          null => '連結日曆',
                        },
                        detail: calendar.chosen == null
                            ? '定期扣款與卡費繳款日放進 Google 日曆，由日曆提醒你'
                            : '定期扣款與卡費繳款日會自動更新；點此更換或停止',
                        icon: Glyph.calendar,
                        onTap: () => _linkCalendar(calendar),
                      ),
                    ),
                  ],
                  const SectionHead('效能'),
                  SoftPanel(
                    child: Column(
                      children: [
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
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Hue.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Only the preview's made-up book can be reset.
                  if (ledger.journal == null)
                    InkWell(
                      onTap: _reset,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Text('重設範例資料', style: TextStyle(color: Hue.danger)),
                            Spacer(),
                            GlyphIcon(Glyph.reset, color: Hue.danger),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Export extends StatelessWidget {
  const _Export({
    required this.badge,
    required this.title,
    required this.detail,
    required this.onTap,
    this.icon = Glyph.download,
  });

  final String badge;
  final Glyph icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Hue.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(fontSize: 12, color: Hue.muted),
                  ),
                ],
              ),
            ),
            GlyphIcon(icon, color: Hue.muted),
          ],
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
