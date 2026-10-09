import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../demo/ledger.dart';
import '../demo/seed.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import 'dialogs.dart';
import 'nav.dart';

/// 設定與資料: preferences, exporting a month or the whole book, and
/// resetting the demo.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late var _month = (widget.ledger.today.year, widget.ledger.today.month);

  Future<void> _copy(String text, String note) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showNote(context, note);
  }

  String _csv(List<Entry> entries) {
    final ledger = widget.ledger;
    return [
      '日期,類型,金額,帳戶,分類,備註',
      for (final e in entries.reversed)
        [
          '${e.date.year}-${e.date.month}-${e.date.day}',
          e.type.name,
          '${e.amount}',
          ledger.account(e.account).name,
          e.category,
          e.note.replaceAll(',', '，'),
        ].join(','),
    ].join('\n');
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

  Future<void> _reset() async {
    final ok = await confirm(context, '重設演示資料？目前的變更會清除。', '重設', danger: true);
    if (!ok) return;
    widget.ledger.resetTo(demoLedger());
    if (mounted) showNote(context, '已重設演示資料');
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
                    icon: Icons.visibility_outlined,
                    label: '隱藏摘要金額',
                    trailing: Switch(
                      value: ledger.hidden,
                      onChanged: (_) => ledger.toggleHidden(),
                    ),
                  ),
                  const Divider(),
                  const _Setting(
                    icon: Icons.account_balance_wallet_outlined,
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
                            _csv(entries),
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
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _reset,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Text(
                            '重設演示資料',
                            style: TextStyle(color: Hue.danger),
                          ),
                          Spacer(),
                          Icon(Icons.restart_alt, color: Hue.danger),
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

  final IconData icon;
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
  });

  final String badge;
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
            const Icon(Icons.download_outlined, color: Hue.muted),
          ],
        ),
      ),
    );
  }
}
