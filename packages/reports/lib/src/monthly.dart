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
