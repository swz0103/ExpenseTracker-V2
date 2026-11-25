import 'dart:math' show min;

/// The highest yearly rate a loan is kept at, in hundredths of a
/// percent: 100%. A rate above it is taken for a typo and refused
/// (D118), not kept as no rate.
const maxLoanRate = 10000;

/// What a rate typed into a loan's form reads as.
sealed class RateReading {
  const RateReading();
}

/// A number, in hundredths of a percent, kept with its sign and however
/// large it is, for the write rules to refuse one below nothing (D116) or
/// above [maxLoanRate] (D118).
final class RateRead extends RateReading {
  const RateRead(this.hundredths);

  final int hundredths;
}

/// Not a number: 「abc」, 「.」, 「--1」, said so rather than kept as no
/// rate (D118).
final class RateUnreadable extends RateReading {
  const RateUnreadable();
}

/// Whole percents past which a rate reads as just this many: it is
/// refused either way, and no longer digits need be carried.
const _wholeCap = 1000000;

/// Reads a rate as typed, such as 「2.15」 or 「-1」, in hundredths of a
/// percent: from the digits themselves, not through a double, which holds
/// 1.005 as 1.00499...: past two places it rounds half up, as written.
/// Empty text is [RateUnreadable]; a field that may be left empty asks
/// before reading it.
RateReading readRate(String typed) {
  var text = typed.trim();
  final negative = text.startsWith('-');
  if (negative) text = text.substring(1);
  final match = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(text);
  if (match == null || !text.contains(RegExp(r'\d'))) {
    return const RateUnreadable();
  }
  final wholeDigits = match[1]!.replaceFirst(RegExp(r'^0+'), '');
  final whole = wholeDigits.length > '$_wholeCap'.length
      ? _wholeCap
      : min(int.parse(wholeDigits.isEmpty ? '0' : wholeDigits), _wholeCap);
  final decimals = match[2] ?? '';
  final kept = int.parse(decimals.padRight(2, '0').substring(0, 2));
  final next = decimals.length > 2 ? int.parse(decimals[2]) : 0;
  final hundredths = whole * 100 + kept + (next >= 5 ? 1 : 0);
  return RateRead(negative ? -hundredths : hundredths);
}

/// A rate as typed, in hundredths of a percent; null when it is not a
/// number from 0 to [maxLoanRate] ([readRate]).
int? rateOf(String typed) => switch (readRate(typed)) {
  RateRead(:final hundredths)
      when hundredths >= 0 && hundredths <= maxLoanRate =>
    hundredths,
  _ => null,
};

/// A rate in hundredths of a percent as the form shows it: 215 as 2.15.
String rateText(int? rate) {
  if (rate == null) return '';
  final whole = rate ~/ 100;
  final cents = rate % 100;
  if (cents == 0) return '$whole';
  return cents % 10 == 0
      ? '$whole.${cents ~/ 10}'
      : '$whole.${'$cents'.padLeft(2, '0')}';
}
