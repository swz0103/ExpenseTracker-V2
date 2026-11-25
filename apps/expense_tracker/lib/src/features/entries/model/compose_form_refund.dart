import 'package:core/time/calendar_day.dart' show BusinessDate;
import 'package:core/fx/dated_figures.dart' show FoundOn;

import '../../../core/ledger/ledger.dart';
import '../../../core/messages/amount_messages.dart';
import 'compose_form.dart';

/// What a refund being written gives back of its purchase, and the worth
/// at home of a foreign entry.
extension RefundFields on ComposeForm {
  /// [home], else the refunded share of the purchase's worth (the rest of
  /// it for the refund that gives back the rest, D62), else the amount at
  /// the rate of its day (D58: that day's board, else the nearest earlier
  /// day's, else today's); null without a rate.
  int? get homeValue {
    final typed = home;
    if (typed != null) return typed;
    if (refundBeingWritten?.home case final share?) return share;
    return ledger.marketData.toHomeOn(amount, currency, date);
  }

  /// What is said under [homeValue] of the rate it is worked out at; null
  /// once typed, or without a rate. A board kept for the entry's day or
  /// before it is named by its day (D58), today's as today's; a day gone
  /// by with no board kept on or before it is valued at today's rate only
  /// as an estimate (R5).
  String? get homeRateLine {
    if (home != null) return null;
    final today = ledger.today;
    return switch (ledger.marketData.rateOn(currency, date)) {
      null => null,
      (:final figure, found: FoundOn.today, of: _) =>
        date.isBefore(today)
            ? estimatedAtTodaysRate(figure)
            : todaysRate(figure),
      (:final figure, :final of?, found: _) when of != BusinessDate.of(today) =>
        rateOfDay(figure, of.asUtcMidnight, today: today),
      (:final figure, of: _, found: _) => todaysRate(figure),
    };
  }

  /// The spending the entry gives back: [refunded], or the one a refund
  /// being changed gives back; null for any other entry.
  Entry? get refundedPurchase {
    final opened = refunded;
    if (opened != null) return opened;
    final of = editing?.refundOf;
    return of == null ? null : ledger.entries.byId(of);
  }

  /// What the refund being written gives back of its purchase, as the
  /// ledger's one rule shares it (`refundShare`: its worth, split and
  /// tags, D62, D65); null when it is no refund.
  RefundShare? get refundBeingWritten {
    final original = refundedPurchase;
    if (original == null || type != EntryType.income) return null;
    return refundShare(
      original,
      amount,
      earlier: [
        for (final e in ledger.entries.refundsOf(original.id))
          if (e.id != editing?.id) e,
      ],
    );
  }
}
