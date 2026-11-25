import 'package:core/foundation_values.dart';

import '../model/trade_values.dart';

/// Taiwan's tax and premium rates in force from [from]. Suggestions use
/// the rates of the trade's or payment's own date, so a change in the law
/// never changes an older suggestion. Taxes are per ten
/// thousand of the gross; the premium in basis points.
final class TaiwanRates {
  const TaiwanRates._({
    required this.from,
    required this.stockTax,
    required this.dayTradeTax,
    required this.etfTax,
    required this.bondEtfTax,
    required this.premiumBasisPoints,
    required this.premiumThreshold,
  });

  final BusinessDate from;
  final int stockTax;
  final int dayTradeTax;
  final int etfTax;

  /// Bond ETFs are exempt from 2017 through 2026 by law; an extension
  /// (proposed to 2036) changes the 2027 row.
  final int bondEtfTax;
  final int premiumBasisPoints;

  /// In whole New Taiwan dollars.
  final int premiumThreshold;

  /// Oldest first, each row the law as enacted from its date; a date past
  /// the last row takes the last row. Day-trade tax is halved from
  /// 2017-04-28 through 2027-12-31 by law; an extension adds a row here.
  /// The 2027 and 2028 rows are not forecasts: they are the end dates the
  /// law in force sets for the bond-ETF exemption and the day-trade
  /// halving.
  static final history = List<TaiwanRates>.unmodifiable([
    TaiwanRates._(
      from: BusinessDate(2016, 1, 1),
      stockTax: 30,
      dayTradeTax: 30,
      etfTax: 10,
      bondEtfTax: 10,
      premiumBasisPoints: 191,
      premiumThreshold: 20000,
    ),
    TaiwanRates._(
      from: BusinessDate(2017, 1, 1),
      stockTax: 30,
      dayTradeTax: 30,
      etfTax: 10,
      bondEtfTax: 0,
      premiumBasisPoints: 191,
      premiumThreshold: 20000,
    ),
    TaiwanRates._(
      from: BusinessDate(2017, 4, 28),
      stockTax: 30,
      dayTradeTax: 15,
      etfTax: 10,
      bondEtfTax: 0,
      premiumBasisPoints: 191,
      premiumThreshold: 20000,
    ),
    TaiwanRates._(
      from: BusinessDate(2021, 1, 1),
      stockTax: 30,
      dayTradeTax: 15,
      etfTax: 10,
      bondEtfTax: 0,
      premiumBasisPoints: 211,
      premiumThreshold: 20000,
    ),
    TaiwanRates._(
      from: BusinessDate(2027, 1, 1),
      stockTax: 30,
      dayTradeTax: 15,
      etfTax: 10,
      bondEtfTax: 10,
      premiumBasisPoints: 211,
      premiumThreshold: 20000,
    ),
    TaiwanRates._(
      from: BusinessDate(2028, 1, 1),
      stockTax: 30,
      dayTradeTax: 30,
      etfTax: 10,
      bondEtfTax: 10,
      premiumBasisPoints: 211,
      premiumThreshold: 20000,
    ),
  ]);

  /// The rates on [date]. Before 2016 there is no suggestion; the user
  /// types what was charged.
  static TaiwanRates on(BusinessDate date) {
    for (final rates in history.reversed) {
      if (rates.from.compareTo(date) <= 0) return rates;
    }
    throw const InvestmentException(InvestmentError.invalidInput);
  }
}
