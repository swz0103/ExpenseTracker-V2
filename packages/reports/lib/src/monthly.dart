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
    this.accountId,
    this.merchantId,
    List<CategoryAllocation> allocations = const [],
    Set<PublicId> tagIds = const {},
  }) : allocations = List.unmodifiable(allocations),
       tagIds = Set.unmodifiable(tagIds) {
    if (income.currency != expense.currency) {
      throw const MoneyException(MoneyError.currencyMismatch);
    }
    if (tagIds.length > 16) {
      throw const FormatException('Too many report tags.');
    }
    if (allocations.isNotEmpty) {
      final effect = income.minorUnits != BigInt.zero
          ? income.minorUnits
          : expense.minorUnits;
      if (effect == BigInt.zero ||
          (income.minorUnits != BigInt.zero &&
              expense.minorUnits != BigInt.zero)) {
        throw const FormatException('Ambiguous category attribution.');
      }
      final ids = <PublicId>{};
      var total = BigInt.zero;
      for (final allocation in allocations) {
        if (allocation.amount.currency != currency) {
          throw const MoneyException(MoneyError.currencyMismatch);
        }
        if (allocation.amount.minorUnits <= BigInt.zero ||
            !ids.add(allocation.categoryId)) {
          throw const FormatException('Invalid category allocation.');
        }
        total += allocation.amount.minorUnits;
      }
      if (total != effect.abs()) {
        throw const FormatException(
          'Category allocations do not match report effect.',
        );
      }
    }
  }

  final PublicId id;
  final BusinessDate date;
  final PostingKind kind;
  final Money income, expense;

  /// The posting's primary account; this attributes report effects, not cash flow.
  final PublicId? accountId;

  /// Saved identity, not today's canonical merchant after a merge.
  final PublicId? merchantId;
  final List<CategoryAllocation> allocations;
  final Set<PublicId> tagIds;
  Currency get currency => income.currency;
  bool get contributes =>
      income.minorUnits != BigInt.zero || expense.minorUnits != BigInt.zero;
}

final class CategoryAllocation {
  const CategoryAllocation(this.categoryId, this.amount);
  final PublicId categoryId;
  final Money amount;
}

final class MonthlyCategoryFact {
  const MonthlyCategoryFact(this.source, this.income, this.expense);
  final MonthlyFact source;
  final Money income, expense;
}

final class MonthlyCategorySummary {
  const MonthlyCategorySummary(
    this.categoryId,
    this.currency,
    this.income,
    this.expense,
    this.net,
    this.facts,
  );

  /// Null means no historical allocation, including transfer fees.
  final PublicId? categoryId;
  final Currency currency;
  final Money income, expense, net;
  final List<MonthlyCategoryFact> facts;
}

final class MonthlyMerchantSummary {
  const MonthlyMerchantSummary(
    this.merchantId,
    this.currency,
    this.income,
    this.expense,
    this.net,
    this.facts,
  );

  /// Null includes entries without a merchant and transfer fees.
  final PublicId? merchantId;
  final Currency currency;
  final Money income, expense, net;
  final List<MonthlyFact> facts;
}

final class MonthlyAccountSummary {
  const MonthlyAccountSummary(
    this.accountId,
    this.currency,
    this.income,
    this.expense,
    this.net,
    this.facts,
  );

  /// Saved posting account; currency is the report effect's denomination.
  final PublicId? accountId;
  final Currency currency;
  final Money income, expense, net;
  final List<MonthlyFact> facts;
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
  MonthlyReport._(
    this.month,
    this.currencies,
    this.categories,
    this.merchants,
    this.accounts,
  );

  final ReportMonth month;
  final List<MonthlyCurrencySummary> currencies;
  final List<MonthlyCategorySummary> categories;
  final List<MonthlyMerchantSummary> merchants;
  final List<MonthlyAccountSummary> accounts;

  factory MonthlyReport.build(ReportMonth month, Iterable<MonthlyFact> source) {
    final grouped = <Currency, List<MonthlyFact>>{};
    final ids = <PublicId>{};
    final allFacts = <MonthlyFact>[];
    for (final fact in source) {
      if (fact.date.year != month.year ||
          fact.date.month != month.month ||
          !ids.add(fact.id)) {
        throw const FormatException('Invalid monthly report facts.');
      }
      allFacts.add(fact);
      if (fact.contributes)
        grouped.putIfAbsent(fact.currency, () => []).add(fact);
    }
    final currencies = grouped.keys.toList()
      ..sort((a, b) {
        final code = a.code.compareTo(b.code);
        return code != 0 ? code : a.scale.compareTo(b.scale);
      });
    final categoryFacts = <(Currency, PublicId?), List<MonthlyCategoryFact>>{};
    final merchantFacts = <(Currency, PublicId?), List<MonthlyFact>>{};
    final accountFacts = <(Currency, PublicId?), List<MonthlyFact>>{};
    for (final fact in allFacts.where((row) => row.contributes)) {
      accountFacts
          .putIfAbsent((fact.currency, fact.accountId), () => [])
          .add(fact);
      merchantFacts
          .putIfAbsent((fact.currency, fact.merchantId), () => [])
          .add(fact);
      final allocations = fact.allocations;
      if (allocations.isEmpty) {
        categoryFacts
            .putIfAbsent((fact.currency, null), () => [])
            .add(MonthlyCategoryFact(fact, fact.income, fact.expense));
      } else {
        for (final allocation in allocations) {
          final units = allocation.amount.minorUnits;
          categoryFacts
              .putIfAbsent((fact.currency, allocation.categoryId), () => [])
              .add(
                MonthlyCategoryFact(
                  fact,
                  Money(
                    fact.currency,
                    fact.income.minorUnits == BigInt.zero
                        ? BigInt.zero
                        : fact.income.minorUnits.isNegative
                        ? -units
                        : units,
                  ),
                  Money(
                    fact.currency,
                    fact.expense.minorUnits == BigInt.zero
                        ? BigInt.zero
                        : fact.expense.minorUnits.isNegative
                        ? -units
                        : units,
                  ),
                ),
              );
        }
      }
    }
    final categoryKeys = categoryFacts.keys.toList()
      ..sort((a, b) {
        final code = a.$1.code.compareTo(b.$1.code);
        if (code != 0) return code;
        final scale = a.$1.scale.compareTo(b.$1.scale);
        if (scale != 0) return scale;
        if (a.$2 == null) return 1;
        if (b.$2 == null) return -1;
        return a.$2!.value.compareTo(b.$2!.value);
      });
    final merchantKeys = merchantFacts.keys.toList()
      ..sort((a, b) {
        final code = a.$1.code.compareTo(b.$1.code);
        if (code != 0) return code;
        final scale = a.$1.scale.compareTo(b.$1.scale);
        if (scale != 0) return scale;
        if (a.$2 == null) return 1;
        if (b.$2 == null) return -1;
        return a.$2!.value.compareTo(b.$2!.value);
      });
    final accountKeys = accountFacts.keys.toList()
      ..sort((a, b) {
        final code = a.$1.code.compareTo(b.$1.code);
        if (code != 0) return code;
        final scale = a.$1.scale.compareTo(b.$1.scale);
        if (scale != 0) return scale;
        if (a.$2 == null) return 1;
        if (b.$2 == null) return -1;
        return a.$2!.value.compareTo(b.$2!.value);
      });
    return MonthlyReport._(
      month,
      List.unmodifiable([
        for (final currency in currencies)
          _summarize(currency, grouped[currency]!),
      ]),
      List.unmodifiable([
        for (final key in categoryKeys)
          _summarizeCategory(key, categoryFacts[key]!),
      ]),
      List.unmodifiable([
        for (final key in merchantKeys)
          _summarizeMerchant(key, merchantFacts[key]!),
      ]),
      List.unmodifiable([
        for (final key in accountKeys)
          _summarizeAccount(key, accountFacts[key]!),
      ]),
    );
  }

  static MonthlyAccountSummary _summarizeAccount(
    (Currency, PublicId?) key,
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
    return MonthlyAccountSummary(
      key.$2,
      key.$1,
      Money(key.$1, income),
      Money(key.$1, expense),
      Money(key.$1, income - expense),
      List.unmodifiable(facts),
    );
  }

  static MonthlyMerchantSummary _summarizeMerchant(
    (Currency, PublicId?) key,
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
    return MonthlyMerchantSummary(
      key.$2,
      key.$1,
      Money(key.$1, income),
      Money(key.$1, expense),
      Money(key.$1, income - expense),
      List.unmodifiable(facts),
    );
  }

  static MonthlyCategorySummary _summarizeCategory(
    (Currency, PublicId?) key,
    List<MonthlyCategoryFact> facts,
  ) {
    final income = facts.fold<BigInt>(
      BigInt.zero,
      (sum, fact) => sum + fact.income.minorUnits,
    );
    final expense = facts.fold<BigInt>(
      BigInt.zero,
      (sum, fact) => sum + fact.expense.minorUnits,
    );
    return MonthlyCategorySummary(
      key.$2,
      key.$1,
      Money(key.$1, income),
      Money(key.$1, expense),
      Money(key.$1, income - expense),
      List.unmodifiable(facts),
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
