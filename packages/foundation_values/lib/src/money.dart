enum MoneyError { invalidInput, precision, overflow, currencyMismatch }

/// Strict decimal minor units as persisted: an optional '-', no leading
/// zeros, no '+', whitespace, '-0' or hex. Throws [FormatException], as
/// [BigInt.parse] does, so decoders keep their error handling.
BigInt parseMinorUnits(String text) {
  if (text.length > 20 || !_minorUnitsPattern.hasMatch(text)) {
    throw FormatException('Invalid minor units', text);
  }
  return BigInt.parse(text);
}

final _minorUnitsPattern = RegExp(r'^(0|-?[1-9][0-9]*)$');

final class MoneyException implements Exception {
  const MoneyException(this.code);
  final MoneyError code;
  @override
  String toString() => 'MoneyException(${code.name})';
}

/// A denomination. Use [Currency.iso] for the ISO 4217 minor units.
final class Currency {
  Currency(this.code, this.scale) {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(code) || scale < 0 || scale > 18) {
      throw const MoneyException(MoneyError.invalidInput);
    }
  }

  /// The ISO 4217 denomination for [code]. Use this instead of guessing a
  /// scale; only the reference table below decides minor units.
  factory Currency.iso(String code) => Currency(code, isoScale(code));

  /// ISO 4217 minor units: listed codes use 0 or 3 decimals, all others 2.
  static int isoScale(String code) {
    if (_zeroDecimal.contains(code)) return 0;
    if (_threeDecimal.contains(code)) return 3;
    return 2;
  }

  static const _zeroDecimal = {
    'BIF',
    'CLP',
    'DJF',
    'GNF',
    'ISK',
    'JPY',
    'KMF',
    'KRW',
    'PYG',
    'RWF',
    'UGX',
    'UYI',
    'VND',
    'VUV',
    'XAF',
    'XOF',
    'XPF',
  };
  static const _threeDecimal = {
    'BHD',
    'IQD',
    'JOD',
    'KWD',
    'LYD',
    'OMR',
    'TND',
  };

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
  static const allocationPolicy = 'largest-remainder-v1';
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
        !_minorUnitsPattern.hasMatch(amount)) {
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

  /// Largest-remainder allocation. Each share is truncated toward zero, then
  /// the leftover minor units go one at a time to the shares with the largest
  /// truncated fractions; earlier shares win ties. Every share is within one
  /// minor unit of its exact proportion, and the shares always sum to the total
  /// (10.00 by 1:2:3 is 1.67 / 3.33 / 5.00, not 1.66 / 3.33 / 5.01).
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
    final sign = minorUnits.isNegative ? -BigInt.one : BigInt.one;
    final magnitude = minorUnits.abs();
    final units = <BigInt>[];
    final fractions = <BigInt>[];
    for (final weight in weights) {
      final product = magnitude * weight;
      units.add(product ~/ totalWeight);
      fractions.add(product.remainder(totalWeight));
    }
    var left = magnitude - units.fold(BigInt.zero, (sum, unit) => sum + unit);
    final order = List<int>.generate(weights.length, (index) => index)
      ..sort((a, b) {
        final byFraction = fractions[b].compareTo(fractions[a]);
        return byFraction != 0 ? byFraction : a.compareTo(b);
      });
    for (final index in order) {
      if (left == BigInt.zero) break;
      units[index] += BigInt.one;
      left -= BigInt.one;
    }
    return List.unmodifiable([
      for (final unit in units) Money(currency, sign * unit),
    ]);
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
