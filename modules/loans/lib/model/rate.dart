import 'dart:math' show min;

import 'package:core/money/typed_text.dart' show halfWidth;
import 'package:ledger_entries/rules.dart' show maxLoanRate;

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

/// Not a number: 「abc」, 「.」, 「--1」, 「2,15」, said so rather than
/// kept as no rate (D118).
final class RateUnreadable extends RateReading {
  const RateUnreadable();
}

/// A rate above nothing that is less than the least one kept, 0.01%:
/// 「0.004」 would be kept as no interest at all, so it is refused and
/// said (review 33).
final class RateTooSmall extends RateReading {
  const RateTooSmall();
}

/// Whole percents past which a rate reads as just this many: it is
/// refused either way, and no longer digits need be carried.
const _wholeCap = 1000000;

/// Reads a rate as typed, such as 「2.15」 or 「-1」, in hundredths of a
/// percent: from the digits themselves, not through a double, which holds
/// 1.005 as 1.00499...: past two places it rounds half up, as written.
/// Full-width digits and dot read as typed on a Chinese keyboard (D89),
/// and one trailing 「%」, with or without a space before it, is the
/// percent the rate is in already: 「２.１５」 and 「2 %」 read 2.15. A
/// comma is not read: 「2,15」 may mean 2.15 or 215.
/// Empty text is [RateUnreadable]; a field that may be left empty asks
/// before reading it. A rate below nothing by however little is kept
/// below nothing, for the write rules to refuse (D116); one above
/// nothing that rounds to 0 is [RateTooSmall].
RateReading readRate(String typed) {
  var text = halfWidth(typed).trim();
  if (text.endsWith('%')) {
    text = text.substring(0, text.length - 1).trimRight();
  }
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
  if (hundredths == 0 && text.contains(RegExp('[1-9]'))) {
    // 「-0.004」 is below nothing all the same; 「0.004」 is no rate kept.
    return negative ? const RateRead(-1) : const RateTooSmall();
  }
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
