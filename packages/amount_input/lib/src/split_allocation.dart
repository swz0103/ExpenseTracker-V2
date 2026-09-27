import 'package:foundation_values/foundation_values.dart';

enum SplitMethod { equal, percentage, ratio }

enum SplitAllocationError {
  rowCount,
  total,
  weight,
  percentageTotal,
  zeroShare,
}

final class SplitAllocationException implements Exception {
  const SplitAllocationException(this.code);
  final SplitAllocationError code;
  @override
  String toString() => 'SplitAllocationException(${code.name})';
}

/// A proposal only: callers must explicitly confirm before changing a draft.
final class SplitAllocation {
  SplitAllocation._(this.amounts, this.remainderMinorUnits);
  static const maxRows = 16;
  static const policy = Money.allocationPolicy;
  final List<Money> amounts;

  /// Minor units added to the last row beyond its truncated ideal share.
  final BigInt remainderMinorUnits;
}

/// Positive decimal weights have at most 18 fractional places and 128 characters.
/// Percentages must total exactly 100. No floating point or implicit rounding.
SplitAllocation proposeSplit(
  Money total, {
  required int rows,
  required SplitMethod method,
  List<String> weights = const [],
}) {
  Never fail(SplitAllocationError code) => throw SplitAllocationException(code);
  if (rows < 2 ||
      rows > SplitAllocation.maxRows ||
      (method == SplitMethod.equal
          ? weights.isNotEmpty
          : weights.length != rows)) {
    fail(SplitAllocationError.rowCount);
  }
  if (total.minorUnits <= BigInt.zero) fail(SplitAllocationError.total);
  List<BigInt> integers;
  if (method == SplitMethod.equal) {
    integers = List.filled(rows, BigInt.one);
  } else {
    final decimals = <(BigInt, int)>[];
    var scale = 0;
    for (final raw in weights) {
      if (raw.length > 128) fail(SplitAllocationError.weight);
      final text = raw.trim();
      if (!RegExp(r'^[0-9]+(?:\.[0-9]{1,18})?$').hasMatch(text)) {
        fail(SplitAllocationError.weight);
      }
      final parts = text.split('.');
      final places = parts.length == 2 ? parts[1].length : 0;
      final value = BigInt.parse(parts.join());
      if (value <= BigInt.zero) fail(SplitAllocationError.weight);
      decimals.add((value, places));
      if (places > scale) scale = places;
    }
    integers = [
      for (final (value, places) in decimals)
        value * BigInt.from(10).pow(scale - places),
    ];
    if (method == SplitMethod.percentage &&
        integers.fold(BigInt.zero, (a, b) => a + b) !=
            BigInt.from(100) * BigInt.from(10).pow(scale)) {
      fail(SplitAllocationError.percentageTotal);
    }
  }
  final amounts = total.allocate(integers);
  if (amounts.any((m) => m.minorUnits == BigInt.zero)) {
    fail(SplitAllocationError.zeroShare);
  }
  final sum = integers.fold(BigInt.zero, (a, b) => a + b);
  final idealLast = total.minorUnits * integers.last ~/ sum;
  return SplitAllocation._(amounts, amounts.last.minorUnits - idealLast);
}
