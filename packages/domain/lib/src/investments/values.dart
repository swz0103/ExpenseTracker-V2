enum InvestmentError {
  invalidInput,
  currencyMismatch,

  /// Taiwan-listed shares trade in whole shares only.
  fractionalShares,
}

final class InvestmentException implements Exception {
  const InvestmentException(this.code);
  final InvestmentError code;
  @override
  String toString() => 'InvestmentException(${code.name})';
}

enum InstrumentKind { stock, etf, bondEtf }

/// Exact positive share quantity, at most 12 decimal places.
final class ShareQuantity {
  ShareQuantity._(this._decimal);
  factory ShareQuantity.parse(String input) =>
      ShareQuantity._(_PositiveDecimal.parse(input));

  final _PositiveDecimal _decimal;
  BigInt get coefficient => _decimal.coefficient;
  int get scale => _decimal.scale;

  /// No fraction of a share.
  bool get isWhole => coefficient % BigInt.from(10).pow(scale) == BigInt.zero;
  @override
  String toString() => _decimal.input;
  @override
  bool operator ==(Object other) =>
      other is ShareQuantity &&
      coefficient == other.coefficient &&
      scale == other.scale;
  @override
  int get hashCode => Object.hash(coefficient, scale);
}

final class _PositiveDecimal {
  const _PositiveDecimal(this.coefficient, this.scale, this.input);
  static _PositiveDecimal parse(String input) {
    if (input.length > 40 ||
        !RegExp(r'^(0|[1-9][0-9]{0,23})(\.[0-9]{1,12})?$').hasMatch(input)) {
      throw const InvestmentException(InvestmentError.invalidInput);
    }
    final parts = input.split('.');
    var coefficient = BigInt.parse(parts.join());
    if (coefficient <= BigInt.zero) {
      throw const InvestmentException(InvestmentError.invalidInput);
    }
    var scale = parts.length == 1 ? 0 : parts[1].length;
    while (scale > 0 && coefficient.remainder(BigInt.from(10)) == BigInt.zero) {
      coefficient ~/= BigInt.from(10);
      scale--;
    }
    return _PositiveDecimal(coefficient, scale, input);
  }

  final BigInt coefficient;
  final int scale;
  final String input;
}
