import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';

/// A civil calendar month, independent of the device timezone.
final class ReportMonth {
  ReportMonth(this.year, this.month) {
    if (year < 1 || year > 9999 || month < 1 || month > 12) {
      throw const FormatException('Invalid report month.');
    }
  }

  final int year, month;
  BusinessDate get first => BusinessDate(year, month, 1);
  BusinessDate get last =>
      BusinessDate(year, month, DateTime.utc(year, month + 1, 0).day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
}

/// Ledger's already classified report effects. Transfer principal and opening
/// balances carry zero; transfer fees, refunds and reversals carry signed
/// consumption/income in their authoritative report currency.
final class MonthlyFact {
  MonthlyFact({
    required this.id,
    required this.date,
    required this.kind,
    required this.income,
    required this.expense,
  }) {
    if (income.currency != expense.currency) {
      throw const MoneyException(MoneyError.currencyMismatch);
    }
  }

  final PublicId id;
  final BusinessDate date;
  final PostingKind kind;
  final Money income, expense;
  Currency get currency => income.currency;
  bool get contributes =>
      income.minorUnits != BigInt.zero || expense.minorUnits != BigInt.zero;
}

final class MonthlyCurrencySummary {
  const MonthlyCurrencySummary(
    this.currency,
    this.income,
    this.expense,
    this.net,
    this.facts,
  );

  final Currency currency;

  /// Signed: an income reversal may make the monthly total negative.
  final Money income;

  /// Signed consumption: refunds and reversals reduce expense in their month.
  final Money expense;
  final Money net;
  final List<MonthlyFact> facts;
}

/// No persisted projection: rebuild deterministically from effective Ledger
/// events. Refuse sums outside Money's supported range instead of overflowing
/// or displaying a partial financial total.
final class MonthlyReport {
  MonthlyReport._(this.month, this.currencies);

  final ReportMonth month;
  final List<MonthlyCurrencySummary> currencies;

  factory MonthlyReport.build(ReportMonth month, Iterable<MonthlyFact> source) {
    final grouped = <Currency, List<MonthlyFact>>{};
    final ids = <PublicId>{};
    for (final fact in source) {
      if (fact.date.year != month.year ||
          fact.date.month != month.month ||
          !ids.add(fact.id)) {
        throw const FormatException('Invalid monthly report facts.');
      }
      if (fact.contributes)
        grouped.putIfAbsent(fact.currency, () => []).add(fact);
    }
    final currencies = grouped.keys.toList()
      ..sort((a, b) {
        final code = a.code.compareTo(b.code);
        return code != 0 ? code : a.scale.compareTo(b.scale);
      });
    return MonthlyReport._(
      month,
      List.unmodifiable([
        for (final currency in currencies)
          _summarize(currency, grouped[currency]!),
      ]),
    );
  }

  static MonthlyCurrencySummary _summarize(
    Currency currency,
    List<MonthlyFact> facts,
  ) {
    final income = facts.fold<BigInt>(
      BigInt.zero,
      (sum, fact) => sum + fact.income.minorUnits,
    );
    final expense = facts.fold<BigInt>(
      BigInt.zero,
      (sum, fact) => sum + fact.expense.minorUnits,
    );
    return MonthlyCurrencySummary(
      currency,
      Money(currency, income),
      Money(currency, expense),
      Money(currency, income - expense),
      List.unmodifiable(facts),
    );
  }
}
