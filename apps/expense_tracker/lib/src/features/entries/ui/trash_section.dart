import 'package:flutter/material.dart';

import '../../../core/ledger/ledger.dart';
import '../../../core/formatting/figures.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/platform/problems.dart';
import '../../../core/widgets/entry_tile.dart';
import '../../../core/design_system/settings_hue.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../core/formatting/dates.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/shape.dart';

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
      if (ledger.entryCommands.restoreTrashed(trashed)) {
        showNote(context, '已放回「${trashed.entry.title}」');
      }
    } on Object catch (error) {
      ErrorLog.instance.record('放回刪除的紀錄', error);
      showNote(context, describeProblem(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final trash = ledger.trash;
    if (trash.all.isEmpty) {
      return const EmptyState(
        glyph: Glyph.trash,
        color: SettingsHue.trash,
        message: '沒有刪除的紀錄',
      );
    }
    final today = ledger.today;
    // Grouped by the day each entry was for, latest day first.
    final days = groupByDay(
      [...trash.all]..sort((a, b) => b.entry.date.compareTo(a.entry.date)),
      (t) => t.entry.date,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColorCard(
          color: SettingsHue.trash,
          child: Row(
            children: [
              const SquareIcon(Glyph.reset, SettingsHue.trash, size: 54),
              const SizedBox(width: Space.s4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${trash.all.length} 筆',
                    style: const TextStyle(
                      fontSize: TextSize.figure,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '保留 $_keptDays 天',
                    style: TextStyle(
                      fontSize: TextSize.body,
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
            padding: const EdgeInsets.fromLTRB(
              Space.s2,
              Space.s4,
              Space.s2,
              Space.s2,
            ),
            child: Text(
              '${formatMEd(day)} 記的',
              style: const TextStyle(
                fontSize: TextSize.body,
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
          const SizedBox(width: Space.s2),
          FilledButton(
            onPressed: () => _restore(context, t),
            style: solidButton(
              Hue.selected,
              ink: Hue.accent,
              minimumSize: Size(56, 44),
              radius: Radii.large,
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
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
