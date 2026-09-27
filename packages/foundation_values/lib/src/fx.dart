import 'money.dart';
import 'time.dart';

enum FxError { invalidInput, precision, currencyMismatch, dateMismatch }

final class FxException implements Exception {
  const FxException(this.code);
  final FxError code;
  @override
  String toString() => 'FxException(${code.name})';
}

/// Positive quote major units per one base major unit, kept as an exact ratio.
/// This is a calculation value, not a provider quote or a persisted posting.
final class FxRate {
  FxRate._(this.base, this.quote, this.numerator, this.denominator);

  factory FxRate.ratio(
    Currency base,
    Currency quote,
    BigInt numerator,
    BigInt denominator,
  ) {
    if (numerator <= BigInt.zero || denominator <= BigInt.zero) {
      throw const FxException(FxError.invalidInput);
    }
    if (numerator.toString().length > 128 ||
        denominator.toString().length > 128) {
      throw const FxException(FxError.precision);
    }
    final gcd = numerator.gcd(denominator);
    final n = numerator ~/ gcd;
    final d = denominator ~/ gcd;
    if (base.code == quote.code && (base != quote || n != d)) {
      throw const FxException(FxError.currencyMismatch);
    }
    return FxRate._(base, quote, n, d);
  }

  factory FxRate.parse(Currency base, Currency quote, String decimal) {
    if (decimal.length > 128 ||
        !RegExp(r'^[0-9]+(\.[0-9]+)?$').hasMatch(decimal)) {
      throw const FxException(FxError.invalidInput);
    }
    final parts = decimal.split('.');
    return FxRate.ratio(
      base,
      quote,
      BigInt.parse(parts.join()),
      BigInt.from(10).pow(parts.length == 1 ? 0 : parts[1].length),
    );
  }

  /// Derived from actual positive principals. Does not overwrite either amount
  /// or claim that a provider supplied this rate.
  factory FxRate.fromAmounts(Money baseAmount, Money quoteAmount) {
    if (baseAmount.minorUnits <= BigInt.zero ||
        quoteAmount.minorUnits <= BigInt.zero) {
      throw const FxException(FxError.invalidInput);
    }
    return FxRate.ratio(
      baseAmount.currency,
      quoteAmount.currency,
      quoteAmount.minorUnits * BigInt.from(10).pow(baseAmount.currency.scale),
      baseAmount.minorUnits * BigInt.from(10).pow(quoteAmount.currency.scale),
    );
  }

  static const roundingPolicy = Money.roundingPolicy;
  final Currency base;
  final Currency quote;
  final BigInt numerator;
  final BigInt denominator;

  FxRate inverse() => FxRate.ratio(quote, base, denominator, numerator);

  /// Cancel common factors before composing. No intermediate Money quantization.
  FxRate then(FxRate next) {
    if (quote != next.base) throw const FxException(FxError.currencyMismatch);
    final left = numerator.gcd(next.denominator);
    final right = next.numerator.gcd(denominator);
    return FxRate.ratio(
      base,
      next.quote,
      (numerator ~/ left) * (next.numerator ~/ right),
      (denominator ~/ right) * (next.denominator ~/ left),
    );
  }

  Money convert(Money input) {
    if (input.currency != base)
      throw const FxException(FxError.currencyMismatch);
    return Money.quantizeRatio(
      quote,
      input.minorUnits * numerator,
      denominator * BigInt.from(10).pow(base.scale),
    );
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'base': base.code,
    'baseScale': base.scale,
    'quote': quote.code,
    'quoteScale': quote.scale,
    'numerator': numerator.toString(),
    'denominator': denominator.toString(),
  };

  factory FxRate.fromJson(Map<String, Object?> json) {
    const fields = {
      'version',
      'base',
      'baseScale',
      'quote',
      'quoteScale',
      'numerator',
      'denominator',
    };
    if (json.length != fields.length ||
        json.keys.any((key) => !fields.contains(key)) ||
        json['version'] is! int ||
        json['version'] != 1 ||
        json['base'] is! String ||
        json['quote'] is! String ||
        json['baseScale'] is! int ||
        json['quoteScale'] is! int) {
      throw const FxException(FxError.invalidInput);
    }
    BigInt integer(Object? value) {
      if (value is! String ||
          value.length > 128 ||
          !RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
        throw const FxException(FxError.invalidInput);
      }
      return BigInt.parse(value);
    }

    try {
      return FxRate.ratio(
        Currency(json['base'] as String, json['baseScale'] as int),
        Currency(json['quote'] as String, json['quoteScale'] as int),
        integer(json['numerator']),
        integer(json['denominator']),
      );
    } on MoneyException {
      throw const FxException(FxError.invalidInput);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FxRate &&
      base == other.base &&
      quote == other.quote &&
      numerator == other.numerator &&
      denominator == other.denominator;
  @override
  int get hashCode => Object.hash(base, quote, numerator, denominator);
}

/// Observation date and retrieval time are distinct; request date is never
/// substituted for the provider's date. This value does not validate a provider.
final class FxObservation {
  FxObservation({
    required this.rate,
    required this.source,
    required this.asOf,
    required this.retrievedAt,
  }) {
    if (source.length > 96 ||
        !RegExp(r'^[a-z0-9][a-z0-9._:-]*$').hasMatch(source)) {
      throw const FxException(FxError.invalidInput);
    }
  }
  final FxRate rate;
  final String source;
  final BusinessDate asOf;
  final UtcInstant retrievedAt;

  /// Older observations require an explicit caller policy; future ones never match.
  FxRate rateFor(BusinessDate requested, {bool allowEarlier = false}) {
    if (asOf != requested && !(allowEarlier && asOf.compareTo(requested) < 0)) {
      throw const FxException(FxError.dateMismatch);
    }
    return rate;
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'rate': rate.toJson(),
    'source': source,
    'asOf': asOf.toString(),
    'retrievedAt': retrievedAt.toString(),
  };

  factory FxObservation.fromJson(Map<String, Object?> json) {
    const fields = {'version', 'rate', 'source', 'asOf', 'retrievedAt'};
    if (json.length != fields.length ||
        json.keys.any((key) => !fields.contains(key)) ||
        json['version'] is! int ||
        json['version'] != 1 ||
        json['rate'] is! Map<String, Object?> ||
        json['source'] is! String ||
        json['asOf'] is! String ||
        json['retrievedAt'] is! String) {
      throw const FxException(FxError.invalidInput);
    }
    try {
      return FxObservation(
        rate: FxRate.fromJson(json['rate'] as Map<String, Object?>),
        source: json['source'] as String,
        asOf: BusinessDate.parse(json['asOf'] as String),
        retrievedAt: UtcInstant.parse(json['retrievedAt'] as String),
      );
    } on FormatException {
      throw const FxException(FxError.invalidInput);
    }
  }
}
