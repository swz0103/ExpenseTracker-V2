import 'package:flutter/material.dart';

import '../../../../core/ledger/ledger.dart';
import '../../../../core/look/figures.dart';
import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/problems.dart';
import '../../../../core/ui/entry_tile.dart';
import '../settings_hue.dart';

/// How long a deleted entry is kept before it is gone for good.
const _keptDays = 30;

/// 最近刪除: how many there are and how long they are kept, then each
/// deleted entry under the day it was for, with how many days it has
/// left and 放回.
class TrashSection extends StatelessWidget {
  const TrashSection({super.key, required this.ledger});

  final Ledger ledger;

  void _restore(BuildContext context, Trashed trashed) {
    try {
      if (ledger.restoreTrashed(trashed)) {
        showNote(context, '已放回「${trashed.entry.title}」');
      }
    } on Object catch (error) {
      showNote(context, describeProblem(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final trash = ledger.trash;
    if (trash.isEmpty) {
      return const EmptyState(
        glyph: Glyph.trash,
        color: SettingsHue.trash,
        message: '沒有刪除的紀錄',
      );
    }
    final today = ledger.today;
    // Grouped by the day each entry was for, latest day first.
    final days = <DateTime, List<Trashed>>{};
    for (final t in [
      ...trash,
    ]..sort((a, b) => b.entry.date.compareTo(a.entry.date))) {
      final d = t.entry.date;
      days.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(t);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColorCard(
          color: SettingsHue.trash,
          child: Row(
            children: [
              const SquareIcon(Glyph.reset, SettingsHue.trash, size: 54),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${trash.length} 筆',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '保留 $_keptDays 天',
                    style: TextStyle(
                      fontSize: 14,
                      color: deepOf(SettingsHue.trash),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        for (final MapEntry(key: day, value: group) in days.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
            child: Text(
              '${day.month}/${day.day} 週${weekdayNames[day.weekday - 1]} 記的',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Hue.muted,
              ),
            ),
          ),
          QuoteBoard([for (final t in group) _row(context, t, today)]),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, Trashed t, DateTime today) {
    final e = t.entry;
    final (glyph, color) = entryMark(ledger, e);
    final left = _keptDays - today.difference(t.on).inDays;
    final account = ledger.account(e.account).name;
    return QuoteRow(
      lead: SquareIcon(glyph, color, size: 44),
      title: [
        e.title,
        if (e.merchant.isNotEmpty && e.merchant != e.title) e.merchant,
      ].join(' · '),
      detail: [
        if (e.category.isNotEmpty) e.category,
        account,
        '還剩 ${left.clamp(0, _keptDays)} 天',
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RowFigure(ledger.orDots(groupDigits(e.amount))),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: () => _restore(context, t),
            style: FilledButton.styleFrom(
              backgroundColor: Hue.selected,
              foregroundColor: Hue.accent,
              minimumSize: const Size(56, 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              '放回',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
