import 'package:foundation_values/foundation_values.dart';

import 'buy.dart';
import 'sell.dart';

enum StockSplitError {
  invalidRatio,
  emptyLots,
  identityMismatch,
  workspaceMismatch,
  brokerMismatch,
  duplicateLot,
  invalidDate,
  fractionalPrecision,
  staleLots,
}

final class StockSplitException implements Exception {
  const StockSplitException(this.code);
  final StockSplitError code;

  @override
  String toString() => 'StockSplitException(${code.name})';
}

/// One lot's exact share change. The acquisition cost is deliberately unchanged.
final class StockSplitLotChange {
  const StockSplitLotChange({
    required this.before,
    required this.afterQuantity,
  });

  final InvestmentHoldingLot before;
  final ShareQuantity afterQuantity;
  Money get cost => before.remainingCost;
}

/// A forward stock split with no cash-in-lieu. A lot that would need more than
/// twelve fractional share places is rejected instead of silently rounded.
/// Commit must re-read every lot and persist all changes in one transaction.
final class StockSplitPreview {
  StockSplitPreview._({
    required this.id,
    required this.operation,
    required this.effectiveOn,
    required this.broker,
    required this.account,
    required this.instrument,
    required this.newShares,
    required this.oldShares,
    required this.lots,
  });

  factory StockSplitPreview.create({
    required PublicId id,
    required OperationKey operation,
    required BusinessDate effectiveOn,
    required BrokerIdentity broker,
    required InvestmentAccount account,
    required InvestmentInstrument instrument,
    required int newShares,
    required int oldShares,
    required List<InvestmentHoldingLot> lots,
  }) {
    if (newShares <= oldShares || oldShares < 1 || newShares > 1000000000) {
      throw const StockSplitException(StockSplitError.invalidRatio);
    }
    if (operation.workspace != account.workspace ||
        operation.workspace != broker.workspace) {
      throw const StockSplitException(StockSplitError.workspaceMismatch);
    }
    if (account.brokerId != broker.id) {
      throw const StockSplitException(StockSplitError.brokerMismatch);
    }
    if (lots.isEmpty) {
      throw const StockSplitException(StockSplitError.emptyLots);
    }
    final seen = <PublicId>{};
    final changes = <StockSplitLotChange>[];
    for (final lot in lots) {
      if (!seen.add(lot.id)) {
        throw const StockSplitException(StockSplitError.duplicateLot);
      }
      if (lot.investmentAccountId != account.id ||
          lot.instrumentId != instrument.id ||
          lot.remainingCost.currency != instrument.tradingCurrency ||
          lot.id == id) {
        throw const StockSplitException(StockSplitError.identityMismatch);
      }
      if (lot.acquiredOn.compareTo(effectiveOn) > 0) {
        throw const StockSplitException(StockSplitError.invalidDate);
      }
      final units =
          lot.remainingQuantity.coefficient *
          BigInt.from(10).pow(12 - lot.remainingQuantity.scale);
      final expanded = units * BigInt.from(newShares);
      final divisor = BigInt.from(oldShares);
      if (expanded.remainder(divisor) != BigInt.zero) {
        throw const StockSplitException(StockSplitError.fractionalPrecision);
      }
      final afterUnits = expanded ~/ divisor;
      final whole = afterUnits ~/ BigInt.from(10).pow(12);
      final fraction = (afterUnits % BigInt.from(10).pow(12))
          .toString()
          .padLeft(12, '0')
          .replaceFirst(RegExp(r'0+$'), '');
      final text = fraction.isEmpty ? '$whole' : '$whole.$fraction';
      try {
        changes.add(
          StockSplitLotChange(
            before: lot,
            afterQuantity: ShareQuantity.parse(text),
          ),
        );
      } on InvestmentException {
        throw const StockSplitException(StockSplitError.fractionalPrecision);
      }
    }
    changes.sort((a, b) {
      final byDate = a.before.acquiredOn.compareTo(b.before.acquiredOn);
      return byDate != 0
          ? byDate
          : a.before.id.value.compareTo(b.before.id.value);
    });
    return StockSplitPreview._(
      id: id,
      operation: operation,
      effectiveOn: effectiveOn,
      broker: broker,
      account: account,
      instrument: instrument,
      newShares: newShares,
      oldShares: oldShares,
      lots: List.unmodifiable(changes),
    );
  }

  final PublicId id;
  final OperationKey operation;
  final BusinessDate effectiveOn;
  final BrokerIdentity broker;
  final InvestmentAccount account;
  final InvestmentInstrument instrument;
  final int newShares;
  final int oldShares;
  final List<StockSplitLotChange> lots;

  void verifyCurrentLots(List<InvestmentHoldingLot> current) {
    if (current.length != lots.length) {
      throw const StockSplitException(StockSplitError.staleLots);
    }
    final ordered = List<InvestmentHoldingLot>.of(current)
      ..sort((a, b) {
        final byDate = a.acquiredOn.compareTo(b.acquiredOn);
        return byDate != 0 ? byDate : a.id.value.compareTo(b.id.value);
      });
    for (var index = 0; index < ordered.length; index++) {
      final actual = ordered[index];
      final expected = lots[index].before;
      if (actual.id != expected.id ||
          actual.investmentAccountId != expected.investmentAccountId ||
          actual.instrumentId != expected.instrumentId ||
          actual.acquiredOn != expected.acquiredOn ||
          actual.remainingQuantity != expected.remainingQuantity ||
          actual.remainingCost != expected.remainingCost ||
          actual.expectedVersion != expected.expectedVersion) {
        throw const StockSplitException(StockSplitError.staleLots);
      }
    }
  }
}
