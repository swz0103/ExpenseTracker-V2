import 'package:flutter/material.dart';

import '../../../reminders/model/calendar_sync.dart';
import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/ledger/ledger.dart';
import '../../../../core/problems.dart';

/// 連結: a calendar, such as Google Calendar, for the due dates.
class LinksSection extends StatefulWidget {
  const LinksSection({super.key, required this.ledger, required this.calendar});

  final Ledger ledger;
  final CalendarSync calendar;

  @override
  State<LinksSection> createState() => _LinksSectionState();
}

class _LinksSectionState extends State<LinksSection> {
  /// Links a calendar for the due dates, or changes or stops it.
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
      final ledger = widget.ledger;
      if (picked == -1) {
        await calendar.forget(ledger);
        if (mounted) showNote(context, '已停止同步，之後的提醒已從日曆移除');
        if (mounted) setState(() {});
        return;
      }
      await calendar.choose(choices.firstWhere((c) => c.id == picked), ledger);
      final written = await calendar.sync(ledger);
      if (!mounted) return;
      setState(() {});
      showNote(context, written == null ? '日曆沒有同步成功' : '已把 $written 個到期提醒放進日曆');
    } on Object catch (error) {
      if (mounted) showNote(context, '日曆沒有連上：${describeProblem(error)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final calendar = widget.calendar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHead('連結'),
        MenuPanel([
          MenuRow(
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
    );
  }
}
