import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../book/keeper.dart';
import '../demo/seed.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/exchange.dart';
import '../model/ledger.dart';
import '../problems.dart';
import 'dialogs.dart';
import 'import_sheet.dart';
import 'nav.dart';
import 'recovery_code.dart';

/// 設定與資料: preferences, exporting a month or the whole book, the
/// encrypted ledger's backups and keys, and resetting the demo.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.ledger,
    required this.nav,
    this.keeper,
  });

  final Ledger ledger;
  final Nav nav;
  final Keeper? keeper;

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
    final keeper = widget.keeper;
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
      final code = keeper.hasPassword ? null : await keeper.newRecoveryCode();
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
        showNote(context, '已匯出備份檔');
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
    final code = await keeper.newRecoveryCode();
    if (mounted) await showRecoveryCode(context, code);
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
                          detail: '貼上其他記帳 App 或本 App 匯出的 CSV',
                          icon: Glyph.add,
                          onTap: () => importInto(context, ledger),
                        ),
                        const Divider(),
                        _Export(
                          badge: '發票',
                          title: '匯入電子發票',
                          detail: '貼上財政部載具消費明細，自動帶入商家與分類',
                          icon: Glyph.add,
                          onTap: () =>
                              importInto(context, ledger, invoices: true),
                        ),
                      ],
                    ),
                  ),
                  if (widget.keeper case final keeper?) ...[
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
