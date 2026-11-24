import 'dart:async';

import 'package:flutter/material.dart';
import 'package:core/constants/retention.dart';

import '../../../core/ledger/ledger.dart';
import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/design_system/dialogs.dart' show confirm;
import '../../../core/messages/problem_messages.dart';
import '../../../core/widgets/entry_tile.dart';
import '../../../core/design_system/settings_colors.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/diagnostics/error_log.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/shape.dart';

/// 最近刪除: how many there are and how long they are kept, then each
/// deleted entry under the day it was for, with how many days it has
/// left and 放回.
class TrashSection extends StatelessWidget {
  const TrashSection({super.key, required this.ledger});

  final Ledger ledger;

  /// Puts [trashed] back, first asking what stands in its way (D78): an
  /// account closed since, or a refund's purchase deleted too.
  Future<void> _restore(BuildContext context, Trashed trashed) async {
    final hold = ledger.entryCommands.holdOf(trashed);
    final question = restoreQuestion(hold);
    var reopen = false;
    var withOriginal = false;
    if (question != null) {
      final (title, action, body) = question;
      final ok = await confirm(context, title, action, body: body);
      if (!ok || !context.mounted) return;
      reopen = hold is ClosedAccounts;
      withOriginal = hold is OriginalInTrash;
    }
    try {
      if (ledger.entryCommands.restoreTrashed(
        trashed,
        reopen: reopen,
        withOriginal: withOriginal,
      )) {
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
        color: SettingsColors.trash,
        message: '沒有刪除的紀錄',
      );
    }
    final today = ledger.today;
    // Grouped by the day each entry was for, latest day first.
    final days = groupByDay(
      [...trash.all]..sort((a, b) {
        final byDay = b.entry.date.compareTo(a.entry.date);
        // Within a day, the later written first (D76).
        return byDay != 0 ? byDay : (b.order ?? 0).compareTo(a.order ?? 0);
      }),
      (t) => t.entry.date,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColorCard(
          color: SettingsColors.trash,
          child: Row(
            children: [
              const SquareIcon(Glyph.reset, SettingsColors.trash, size: 54),
              const SizedBox(width: Space.s4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    countOf(trash.all.length, CountUnit.entries),
                    style: const TextStyle(
                      fontSize: TextSize.figure,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '保留 ${countOf(trashRetentionDays, CountUnit.days)}',
                    style: TextStyle(
                      fontSize: TextSize.body,
                      color: deepOf(SettingsColors.trash),
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
                color: AppColors.muted,
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
    final left = trashRetentionDays - today.difference(t.on).inDays;
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
        '還剩 ${countOf(left.clamp(0, trashRetentionDays), CountUnit.days)}',
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RowFigure(ledger.orDots(groupDigits(e.amount))),
          const SizedBox(width: Space.s2),
          FilledButton(
            onPressed: () => unawaited(_restore(context, t)),
            style: solidButton(
              AppColors.selected,
              ink: AppColors.accent,
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

/// What to ask before putting an entry back that [hold] stands in the way
/// of (D78): the title, the yes and the words under it; null when nothing
/// does.
(String, String, String)? restoreQuestion(RestoreHold? hold) => switch (hold) {
  null => null,
  ClosedAccounts(:final accounts) => (
    '「${accounts.map((a) => a.name).join('」「')}」已封存',
    '解除封存並放回',
    '這筆用到已封存的帳戶，要解除封存再放回嗎？',
  ),
  OriginalInTrash(:final original) => (
    '原消費也在最近刪除',
    '一起放回',
    '這筆退款的原消費「${original.entry.title}」也已刪除，要一起放回嗎？',
  ),
  OriginalGone() => ('原消費已永久刪除', '仍要放回', '這筆退款的原消費已不在帳本，放回後不會沖回任何消費。'),
};
