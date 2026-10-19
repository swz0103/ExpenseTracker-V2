part of 'posting.dart';

/// Remaining authority in the original expense denomination. Cash received may
/// use another currency, but can never change this limit or its attribution.
final class RefundBudget {
  RefundBudget({
    required this.originalId,
    required this.originalDate,
    required Money amount,
    List<Allocation> allocations = const [],
  }) : remaining = amount,
       allocations = List.unmodifiable(allocations) {
    _positive(amount);
    _allocations(amount, allocations);
    if (allocations.any((a) => a.expectedCategoryVersion == null)) {
      throw const LedgerException(LedgerError.refundReference);
    }
  }
  RefundBudget._(
    this.originalId,
    this.originalDate,
    this.remaining,
    this.allocations,
  );
  final PublicId originalId;
  final BusinessDate originalDate;
  final Money remaining;
  final List<Allocation> allocations;

  RefundBudget consume({
    required Money amount,
    required BusinessDate date,
    required List<Allocation> allocations,
  }) {
    _positive(amount);
    if (amount.currency != remaining.currency) {
      throw const LedgerException(LedgerError.currencyMismatch);
    }
    if (date.compareTo(originalDate) < 0) {
      throw const LedgerException(LedgerError.refundReference);
    }
    if (amount.minorUnits > remaining.minorUnits) {
      throw const LedgerException(LedgerError.refundLimit);
    }
    _allocations(amount, allocations);
    if (this.allocations.isEmpty != allocations.isEmpty) {
      throw const LedgerException(LedgerError.refundReference);
    }
    final available = {for (final a in this.allocations) a.categoryId: a};
    for (final a in allocations) {
      final prior = available[a.categoryId];
      if (prior == null ||
          prior.expectedCategoryVersion != a.expectedCategoryVersion) {
        throw const LedgerException(LedgerError.refundReference);
      }
      if (a.amount.minorUnits > prior.amount.minorUnits) {
        throw const LedgerException(LedgerError.refundLimit);
      }
      final left = prior.amount - a.amount;
      if (left.minorUnits == BigInt.zero) {
        available.remove(a.categoryId);
      } else {
        available[a.categoryId] = Allocation(
          a.categoryId,
          left,
          expectedCategoryVersion: a.expectedCategoryVersion,
        );
      }
    }
    return RefundBudget._(
      originalId,
      originalDate,
      remaining - amount,
      List.unmodifiable(available.values),
    );
  }
}
