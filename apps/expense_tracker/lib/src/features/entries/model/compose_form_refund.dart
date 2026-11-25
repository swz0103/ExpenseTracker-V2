import '../../../core/ledger/ledger.dart';
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
