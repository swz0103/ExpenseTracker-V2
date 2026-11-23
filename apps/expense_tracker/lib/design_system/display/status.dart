/// How every status is shown: for each status value, its words, its
/// colour, its glyph, what a screen reader says, and a stable id for the
/// home widget. The only place status words are written; whether a state
/// holds is decided by the rules (`packages/domain` for cards and
/// holdings, `src/core/ledger/rules/` for budgets, recurring items and
/// advances), never here and never on a screen.
library;

import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:domain/credit_cards.dart';
import 'package:domain/investments.dart' show HoldingStatus;
import 'package:flutter/widgets.dart';

import '../../src/core/design_system/glyphs.dart';
import '../../src/core/design_system/shape.dart';
import '../../src/core/design_system/spacing.dart';
import '../../src/core/design_system/theme.dart';
import '../../src/core/formatting/dates.dart';
import '../../src/core/ledger/rules/advance_rules.dart';
import '../../src/core/ledger/rules/budget_rules.dart';
import '../../src/core/ledger/rules/recurring_rules.dart';
import 'amount.dart';
import 'status_messages.dart';

export 'status_messages.dart';

/// One status as it is shown: [words] on screen, in [color] with
/// [glyph], read out as [spoken]; [id] names the state for the home
/// widget, which shows the words it is given and colours by the id.
final class StatusLook {
  const StatusLook({
    required this.id,
    required this.words,
    required this.color,
    required this.glyph,
    this.alerts = false,
    String? spoken,
  }) : spoken = spoken ?? words;

  final String id;
  final String words;
  final Color color;
  final Glyph glyph;
  final String spoken;

  /// Whether the state asks for attention: the one treatment for it is
  /// the [StatusBadge].
  final bool alerts;
}

/// A card's last statement on screen: 已繳清, 11/20 繳款, 今天繳款 or
/// 已逾期 2 天, short enough for an account card's line; read out with
/// the due day and the days left or late. The same words on the card's
/// page, the account list and 總覽.
StatusLook cardBillLook(CardBillStatus status) => switch (status) {
  BillNotYetBilled() => const StatusLook(
    id: 'notBilled',
    words: StatusWords.notBilled,
    color: AppColors.muted,
    glyph: Glyph.card,
  ),
  BillDue(:final dueOn, :final daysLeft) => StatusLook(
    id: 'due',
    words: '${formatMd(_day(dueOn))} 繳款',
    spoken:
        '${formatMd(_day(dueOn))} 繳款，還有 ${countOf(daysLeft, CountUnit.days)}',
    color: AppColors.muted,
    glyph: Glyph.calendar,
  ),
  BillDueToday() => const StatusLook(
    id: 'dueToday',
    words: StatusWords.dueTodayCard,
    color: Palette.gold,
    glyph: Glyph.bell,
    alerts: true,
  ),
  BillOverdue(:final dueOn, :final days) => StatusLook(
    id: 'overdue',
    words: '${StatusWords.overdue} ${countOf(days, CountUnit.days)}',
    spoken:
        '${formatMd(_day(dueOn))} 繳款，${StatusWords.overdue} ${countOf(days, CountUnit.days)}',
    color: AppColors.negative,
    glyph: Glyph.bell,
    alerts: true,
  ),
  BillPaid() => const StatusLook(
    id: 'paid',
    words: StatusWords.paid,
    color: AppColors.positive,
    glyph: Glyph.check,
  ),
};

DateTime _day(BusinessDate d) => DateTime.utc(d.year, d.month, d.day);

/// A budget on screen: within, 快用完 or 超支. Its badge is the one
/// treatment of an alert; the figure beside it is written after
/// [budgetLead].
StatusLook budgetLook(BudgetStatus status) => switch (status) {
  BudgetWithin() => const StatusLook(
    id: 'within',
    words: StatusWords.left,
    color: AppColors.muted,
    glyph: Glyph.gauge,
  ),
  BudgetNear() => const StatusLook(
    id: 'near',
    words: StatusWords.near,
    color: Palette.gold,
    glyph: Glyph.hourglass,
    alerts: true,
  ),
  BudgetOver() => const StatusLook(
    id: 'over',
    words: StatusWords.over,
    color: AppColors.negative,
    glyph: Glyph.gauge,
    alerts: true,
  ),
};

/// The word before a budget's figure: 剩 what is left, or 超支 by how
/// much it is over.
String budgetLead(BudgetStatus status) =>
    status is BudgetOver ? StatusWords.over : StatusWords.left;

/// The figure after [budgetLead]: what is left, or how much over.
int budgetFigure(BudgetStatus status) => switch (status) {
  BudgetWithin(:final left) || BudgetNear(:final left) => left,
  BudgetOver(:final by) => by,
};

/// A holding on screen: held, or 已賣光.
StatusLook holdingLook(HoldingStatus status) => switch (status) {
  HoldingStatus.held => const StatusLook(
    id: 'held',
    words: StatusWords.held,
    color: AppColors.ink,
    glyph: Glyph.pie,
  ),
  HoldingStatus.soldOut => const StatusLook(
    id: 'soldOut',
    words: StatusWords.soldOut,
    color: AppColors.muted,
    glyph: Glyph.check,
  ),
};

/// One period of a recurring item on screen.
StatusLook recurringLook(RecurringPeriodStatus status) => switch (status) {
  RecurringPeriodStatus.upcoming => const StatusLook(
    id: 'upcoming',
    words: StatusWords.upcoming,
    color: AppColors.muted,
    glyph: Glyph.calendar,
  ),
  RecurringPeriodStatus.due => const StatusLook(
    id: 'due',
    words: StatusWords.due,
    color: AppColors.accent,
    glyph: Glyph.bell,
  ),
  RecurringPeriodStatus.booked => const StatusLook(
    id: 'booked',
    words: StatusWords.booked,
    color: AppColors.positive,
    glyph: Glyph.check,
  ),
  RecurringPeriodStatus.skipped => const StatusLook(
    id: 'skipped',
    words: StatusWords.skipped,
    color: AppColors.faint,
    glyph: Glyph.next,
  ),
  RecurringPeriodStatus.paused => const StatusLook(
    id: 'paused',
    words: StatusWords.paused,
    color: AppColors.faint,
    glyph: Glyph.hourglass,
  ),
};

/// A sum paid for someone on screen.
StatusLook advanceLook(AdvanceStatus status) => switch (status) {
  AdvanceStatus.open => const StatusLook(
    id: 'open',
    words: StatusWords.open,
    color: AppColors.muted,
    glyph: Glyph.hourglass,
  ),
  AdvanceStatus.partlySettled => const StatusLook(
    id: 'partlySettled',
    words: StatusWords.partlySettled,
    color: Palette.gold,
    glyph: Glyph.coins,
  ),
  AdvanceStatus.settled => const StatusLook(
    id: 'settled',
    words: StatusWords.settled,
    color: AppColors.positive,
    glyph: Glyph.check,
  ),
};

/// The one visual treatment of a status that asks for attention: its
/// words on a small block of its colour.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.look, {super.key});

  final StatusLook look;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s2,
        vertical: Space.half,
      ),
      decoration: BoxDecoration(
        color: look.color,
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Text(
        look.words,
        semanticsLabel: look.spoken,
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          fontSize: TextSize.caption,
          fontWeight: FontWeight.w800,
          color: AppColors.onAccent,
        ),
      ),
    );
  }
}

/// The words of a day of recurring items once each is booked or let go:
/// 已入帳, 已略過, or both when the day has some of each.
String settledDayWords(Iterable<RecurringPeriodStatus> statuses) {
  final booked = statuses.contains(RecurringPeriodStatus.booked);
  final skipped = statuses.contains(RecurringPeriodStatus.skipped);
  return [
    if (booked) StatusWords.booked,
    if (skipped) StatusWords.skipped,
  ].join(' · ');
}
