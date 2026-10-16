import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../book/keeper.dart';
import '../demo/exchange.dart';
import '../demo/ledger.dart';
import '../demo/seed.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'dialogs.dart';
import 'import_sheet.dart';
import 'nav.dart';

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

  String _json() {
    final ledger = widget.ledger;
    final entries = <Map<String, Object?>>[];
    for (var back = 0; back < 12; back++) {
      final date = DateTime.utc(ledger.today.year, ledger.today.month - back);
      for (final e in ledger.entriesIn(date.year, date.month)) {
        entries.add({
          'date': e.date.toIso8601String().substring(0, 10),
          'type': e.type.name,
          'amount': e.amount,
          'account': e.account,
          'category': e.category,
          'note': e.note,
          if (e.to != null) 'to': e.to,
          if (e.holding != null) 'holding': e.holding,
          if (e.shares != 0) 'shares': e.shares,
        });
      }
    }
    return const JsonEncoder.withIndent('  ').convert({
      'accounts': [
        for (final a in ledger.accounts)
          {'id': a.id, 'name': a.name, 'kind': a.kind.name},
      ],
      'entries': entries,
      'holdings': [
        for (final h in ledger.holdings)
          {'code': h.code, 'shares': h.shares, 'cost': h.cost},
      ],
    });
  }

  Future<void> _backUp(Keeper keeper) async {
    try {
      final path = await keeper.backUp();
      if (mounted) showNote(context, '已備份到 $path');
    } on Object catch (error) {
      if (mounted) showNote(context, '備份失敗（$error）');
    }
  }

  Future<void> _changePassword(Keeper keeper) async {
    final passwords = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
    if (passwords == null) return;
    final (current, next) = passwords;
    try {
      await keeper.changePassword(current, next);
      if (mounted) showNote(context, '密碼已變更');
    } on Object catch (error) {
      if (!mounted) return;
      final wrong = '$error'.contains('wrongSecret');
      final weak = '$error'.contains('weakPassword');
      showNote(
        context,
        wrong
            ? '目前的密碼不正確'
            : weak
            ? '新密碼至少要 12 個字'
            : '無法變更密碼（$error）',
      );
    }
  }

  Future<void> _newRecovery(Keeper keeper) async {
    final ok = await confirm(context, '換一組新的救援碼？舊的會立刻失效。', '更換');
    if (!ok) return;
    final code = await keeper.newRecoveryCode();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('新的救援碼'),
        content: SelectableText(
          code,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: code)),
            child: const Text('複製'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('我已存好'),
          ),
        ],
      ),
    );
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
                  const SectionHead('日常偏好'),
                  _Setting(
                    icon: Glyph.eye,
                    label: '隱藏金額',
                    trailing: Switch(
                      value: ledger.hidden,
                      onChanged: (_) => ledger.toggleHidden(),
                    ),
                  ),
                  const Divider(),
                  const _Setting(
                    icon: Glyph.cash,
                    label: '記帳幣別',
                    trailing: Text('TWD', style: TextStyle(color: Hue.muted)),
                  ),
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
                          onTap: () => _copy(
                            toCsv(ledger, entries),
                            '已複製 ${entries.length} 筆紀錄的 CSV',
                          ),
                        ),
                        const Divider(),
                        _Export(
                          badge: 'JSON',
                          title: '下載完整帳本',
                          detail: '帳戶、紀錄與持股',
                          onTap: () => _copy(_json(), '已複製完整帳本 JSON'),
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
                            title: '立即備份',
                            detail: '每週會自動備份，保留最近 5 份',
                            onTap: () => _backUp(keeper),
                          ),
                          const Divider(),
                          _Export(
                            badge: '密碼',
                            title: '變更密碼',
                            detail: '至少 12 個字',
                            icon: Glyph.edit,
                            onTap: () => _changePassword(keeper),
                          ),
                          const Divider(),
                          _Export(
                            badge: '救援',
                            title: '更換救援碼',
                            detail: '舊的救援碼會失效',
                            icon: Glyph.reset,
                            onTap: () => _newRecovery(keeper),
                          ),
                          const Divider(),
                          _Export(
                            badge: '鎖定',
                            title: '鎖定帳本',
                            detail: '回到輸入密碼的畫面',
                            icon: Glyph.next,
                            onTap: keeper.lock,
                          ),
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

class _Setting extends StatelessWidget {
  const _Setting({
    required this.icon,
    required this.label,
    required this.trailing,
  });

  final Glyph icon;
  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          IconBadge(icon, Hue.gold, size: 36),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 15)),
          const Spacer(),
          trailing,
        ],
      ),
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
  const _PasswordDialog();

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
    return AlertDialog(
      title: const Text('變更密碼'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          field(_current, '目前的密碼'),
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
        FilledButton(onPressed: _submit, child: const Text('變更')),
      ],
    );
  }
}
