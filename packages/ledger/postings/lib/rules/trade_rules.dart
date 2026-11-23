import 'package:kernel/kernel.dart';
import 'package:ledger_trade_costs/calc/settlement.dart';
import 'package:ledger_trade_costs/model/trade_values.dart';

import '../calc/lots.dart';
import '../model/intents.dart';
import '../model/vocabulary.dart';

// How the trades post: each stock's shares are lots on its holding
// account (sub = the intent that made the lot), worked by the app's own
// lot arithmetic (calc/lots.dart) and its one rule for a trade's money
// (settlementAmount). A sale reads the lots before it: the holding's
// stream posts the later trades again when an earlier one changes.

/// The currency of [code]'s holding account, or a refusal.
(CurrencyCode?, Refused?) _holdingCurrency(RuleContext context, String code) {
  final currency = context.accounts[holdingAccount(code)]?.currency;
  return currency == null
      ? (null, Refused('noHoldingAccount', code))
      : (currency, null);
}

/// [lines] and [more], or the first refusal among them.
Posted _join(List<Line> lines, List<Posted> more) {
  final all = [...lines];
  for (final posted in more) {
    switch (posted) {
      case Lines(lines: final some):
        all.addAll(some);
      case Refused():
        return posted;
    }
  }
  return Lines(all);
}

final class OpeningPositionRule implements PostingRule<OpeningPosition> {
  const OpeningPositionRule();

  @override
  Iterable<String> streams(OpeningPosition i) => [Streams.holding(i.code)];

  @override
  Posted post(OpeningPosition i, RuleContext context) {
    final (currency, refused) = _holdingCurrency(context, i.code);
    if (currency == null) return refused!;
    return Lines([
      Line(
        holdingAccount(i.code),
        i.cost,
        currency,
        quantity: quantityOfShares(i.shares),
        sub: i.id.value,
      ),
      Line(Fixed.realisedGains, -i.realised, currency, sub: i.code),
      Line(Fixed.dividends, -i.dividends, currency, sub: i.code),
      Line(Fixed.openingPositions, i.realised + i.dividends - i.cost, currency),
    ]);
  }
}

/// What the purchase paid, fee and all, is what its lot cost.
final class BuyRule implements PostingRule<Buy> {
  const BuyRule();

  @override
  Iterable<String> streams(Buy i) => [Streams.holding(i.code)];

  @override
  Posted post(Buy i, RuleContext context) {
    final (currency, refused) = _holdingCurrency(context, i.code);
    if (currency == null) return refused!;
    final paid = settlementAmount(TradeKind.buy, gross: i.gross, fee: i.fee);
    return Lines([
      Line(i.cash, paid, currency),
      Line(
        holdingAccount(i.code),
        -paid,
        currency,
        quantity: quantityOfShares(i.shares),
        sub: i.id.value,
      ),
    ]);
  }
}

/// The shares sold come off the lots before it; what they cost against
/// what came in is the gain, kept by stock.
final class SellRule implements PostingRule<Sell> {
  const SellRule();

  @override
  Iterable<String> streams(Sell i) => [Streams.holding(i.code)];

  @override
  Posted post(Sell i, RuleContext context) {
    final (currency, refused) = _holdingCurrency(context, i.code);
    if (currency == null) return refused!;
    final holding = holdingAccount(i.code);
    final sold = sale(
      lotsOf(context.before(holding)),
      i.shares,
      average: i.average,
    );
    if (sold == null) return Refused('oversold', i.code);
    final got = settlementAmount(
      TradeKind.sell,
      gross: i.gross,
      fee: i.fee,
      tax: i.tax,
    );
    return _join(
      [
        Line(i.cash, got, currency),
        Line(Fixed.realisedGains, sold.cost - got, currency, sub: i.code),
      ],
      [lotLines(holding, sold.changes, currency)],
    );
  }
}

/// A cash dividend, shares given, a split, or a capital reduction: one
/// kind today, told apart as the holdings tell them.
final class DividendRule implements PostingRule<Dividend> {
  const DividendRule();

  @override
  Iterable<String> streams(Dividend i) =>
      i.shares == 0 || i.code.isEmpty ? const [] : [Streams.holding(i.code)];

  @override
  Posted post(Dividend i, RuleContext context) {
    final currency = context.accounts[i.cash]?.currency == null
        ? null
        : homeCurrency;
    if (currency == null) return Refused('notAMoneyAccount', i.cash.value);
    final cash = _cash(i, currency);
    if (i.shares == 0) return Lines(cash);
    final (held, refused) = _holdingCurrency(context, i.code);
    if (held == null) return refused!;
    final holding = holdingAccount(i.code);
    final lots = lotsOf(context.before(holding));
    final had = sharesHeld(lots);
    Line realised(int amount) =>
        Line(Fixed.realisedGains, amount, held, sub: i.code);
    if (i.isReduction) return _reduce(i, lots, had, held, realised);
    if (had == 0) {
      // Shares given with nothing held start a lot of their own.
      return Lines([
        ...cash,
        Line(
          holding,
          0,
          held,
          quantity: quantityOfShares(i.shares),
          sub: i.id.value,
        ),
      ]);
    }
    // A stock dividend or a split: every lot grows, keeping its cost; a
    // stock dividend drops the fraction of a share left over.
    final r = reratio(
      lots,
      newShares: had + i.shares,
      oldShares: had,
      currency: held,
      wholeShares: !i.split,
    );
    return _join(
      [...cash, realised(r.dropped)],
      [lotLines(holding, r.changes, held)],
    );
  }

  /// Shares taken back and capital returned, which lowers their cost;
  /// what is returned beyond the cost is a gain. When every share goes,
  /// what the capital did not cover stays on the holding, as the
  /// holdings keep it today.
  Posted _reduce(
    Dividend i,
    List<Lot> lots,
    int had,
    CurrencyCode currency,
    Line Function(int) realised,
  ) {
    if (-i.shares > had) return Refused('oversold', i.code);
    final holding = holdingAccount(i.code);
    final back = settlementAmount(TradeKind.capitalReturn, gross: i.gross);
    final left = had + i.shares;
    if (left == 0) {
      var lowering = back;
      final changes = <LotChange>[];
      for (final lot in lots) {
        final off = lowering < lot.cost ? lowering : lot.cost;
        lowering -= off;
        changes.add((sub: lot.sub, units: -lot.units, cost: -off));
      }
      return _join(
        [Line(i.cash, back, currency), realised(-lowering)],
        [lotLines(holding, changes, currency)],
      );
    }
    final r = reratio(
      lots,
      newShares: left,
      oldShares: had,
      currency: currency,
      capitalReturned: back,
    );
    return _join(
      [Line(i.cash, back, currency), realised(r.lowered + r.dropped - back)],
      [lotLines(holding, r.changes, currency)],
    );
  }

  /// The cash a dividend pays, less what is withheld, as dividends of
  /// its stock.
  List<Line> _cash(Dividend i, CurrencyCode currency) {
    final net = settlementAmount(
      TradeKind.dividend,
      gross: i.gross,
      fee: i.fee,
      tax: i.tax,
    );
    return [
      Line(i.cash, net, currency),
      Line(Fixed.dividends, -net, currency, sub: i.code),
    ];
  }
}

/// An old book's trade its holdings leave out: its money moves, against
/// an account of its own, and no share does.
final class OutOfHoldingsRule implements PostingRule<OutOfHoldings> {
  const OutOfHoldingsRule();

  @override
  Iterable<String> streams(OutOfHoldings intent) => const [];

  @override
  Posted post(OutOfHoldings i, RuleContext context) {
    if (context.accounts[i.cash]?.currency == null) {
      return Refused('notAMoneyAccount', i.cash.value);
    }
    return Lines([
      Line(i.cash, i.settlement, homeCurrency),
      Line(Fixed.outOfHoldings, -i.settlement, homeCurrency),
    ]);
  }
}
