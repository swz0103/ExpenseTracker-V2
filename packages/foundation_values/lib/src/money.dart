enum MoneyError { invalidInput, precision, overflow, currencyMismatch }

final class MoneyException implements Exception {
  const MoneyException(this.code);
  final MoneyError code;
  @override
  String toString() => 'MoneyException(${code.name})';
}

/// A denomination, not an authoritative registry of supported currencies.
final class Currency {
  Currency(this.code, this.scale) {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(code) || scale < 0 || scale > 18) {
      throw const MoneyException(MoneyError.invalidInput);
    }
  }
  final String code;
  final int scale;
  @override
  bool operator ==(Object other) =>
      other is Currency && code == other.code && scale == other.scale;
  @override
  int get hashCode => Object.hash(code, scale);
}

/// Persistable signed minor units. All arithmetic uses BigInt before bounds checks.
final class Money {
  Money(this.currency, this.minorUnits) {
    if (minorUnits < minMinorUnits || minorUnits > maxMinorUnits) {
      throw const MoneyException(MoneyError.overflow);
    }
  }

  static final minMinorUnits = -(BigInt.one << 63);
  static final maxMinorUnits = (BigInt.one << 63) - BigInt.one;
  static const roundingPolicy = 'half-away-from-zero-v1';
  static const allocationPolicy = 'truncate-last-remainder-v1';
  final Currency currency;
  final BigInt minorUnits;

  /// User input must fit the denomination exactly, even when excess digits are 0.
  factory Money.parse(Currency currency, String input) {
    final (coefficient, scale) = _decimal(input);
    if (scale > currency.scale) {
      throw const MoneyException(MoneyError.precision);
    }
    return Money(
      currency,
      coefficient * BigInt.from(10).pow(currency.scale - scale),
    );
  }

  /// Calculation boundary only. Never use this to silently round manual input.
  factory Money.quantize(Currency currency, String calculatedMajorAmount) {
    final (coefficient, scale) = _decimal(calculatedMajorAmount);
    return Money.quantizeRatio(
      currency,
      coefficient,
      BigInt.from(10).pow(scale),
    );
  }

  /// Final calculation boundary for an exact ratio in major units. Manual
  /// input still uses parse and must fit its denomination without rounding.
  factory Money.quantizeRatio(
    Currency currency,
    BigInt numerator,
    BigInt denominator,
  ) {
    if (denominator <= BigInt.zero) {
      throw const MoneyException(MoneyError.invalidInput);
    }
    if (numerator.bitLength > 4096 || denominator.bitLength > 4096) {
      throw const MoneyException(MoneyError.precision);
    }
    final scaled = numerator.abs() * BigInt.from(10).pow(currency.scale);
    var units = scaled ~/ denominator;
    if (scaled.remainder(denominator) * BigInt.two >= denominator) {
      units += BigInt.one;
    }
    return Money(currency, numerator.isNegative ? -units : units);
  }

  factory Money.fromJson(Map<String, Object?> json) {
    final code = json['currency'];
    final scale = json['scale'];
    final amount = json['minorUnits'];
    if (json['version'] != 1 ||
        code is! String ||
        scale is! int ||
        amount is! String ||
        amount.length > 20 ||
        !RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(amount)) {
      throw const MoneyException(MoneyError.invalidInput);
    }
    return Money(Currency(code, scale), BigInt.parse(amount));
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'currency': currency.code,
    'scale': currency.scale,
    'minorUnits': minorUnits.toString(),
  };

  Money operator +(Money other) {
    _requireCurrency(other);
    return Money(currency, minorUnits + other.minorUnits);
  }

  Money operator -(Money other) {
    _requireCurrency(other);
    return Money(currency, minorUnits - other.minorUnits);
  }

  Money operator -() => Money(currency, -minorUnits);

  /// First n-1 shares truncate toward zero; final share receives the remainder.
  List<Money> allocate(List<BigInt> weights) {
    if (weights.isEmpty ||
        weights.length > 10000 ||
        weights.any((weight) => weight <= BigInt.zero)) {
      throw const MoneyException(MoneyError.invalidInput);
    }
    final totalWeight = weights.fold(
      BigInt.zero,
      (sum, weight) => sum + weight,
    );
    var remainder = minorUnits;
    final shares = <Money>[];
    for (var index = 0; index < weights.length - 1; index++) {
      final share = minorUnits * weights[index] ~/ totalWeight;
      shares.add(Money(currency, share));
      remainder -= share;
    }
    shares.add(Money(currency, remainder));
    return List.unmodifiable(shares);
  }

  String get majorText {
    final digits = minorUnits.abs().toString().padLeft(currency.scale + 1, '0');
    final sign = minorUnits.isNegative ? '-' : '';
    if (currency.scale == 0) return '$sign$digits';
    final split = digits.length - currency.scale;
    return '$sign${digits.substring(0, split)}.${digits.substring(split)}';
  }

  void _requireCurrency(Money other) {
    if (currency != other.currency) {
      throw const MoneyException(MoneyError.currencyMismatch);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      currency == other.currency &&
      minorUnits == other.minorUnits;
  @override
  int get hashCode => Object.hash(currency, minorUnits);
}

(BigInt, int) _decimal(String text) {
  // Bound text parsing resources; do not accept exponent, separators or doubles.
  if (text.length > 128 || !RegExp(r'^-?[0-9]+(\.[0-9]+)?$').hasMatch(text)) {
    throw const MoneyException(MoneyError.invalidInput);
  }
  final parts = text.split('.');
  return (BigInt.parse(parts.join()), parts.length == 1 ? 0 : parts[1].length);
}
