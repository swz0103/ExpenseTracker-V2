/// A rate as typed, such as 「2.15」, in hundredths of a percent; null
/// when it is not a number from 0 to 100.
///
/// Read from the digits themselves, not through a double, which holds
/// 1.005 as 1.00499...: past two places it rounds half up, as written.
int? rateOf(String typed) {
  final match = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(typed.trim());
  if (match == null || !typed.contains(RegExp(r'\d'))) return null;
  final decimals = match[2] ?? '';
  final whole = int.tryParse(match[1]!) ?? 0;
  final kept = int.parse(decimals.padRight(2, '0').substring(0, 2));
  final next = decimals.length > 2 ? int.parse(decimals[2]) : 0;
  final hundredths = whole * 100 + kept + (next >= 5 ? 1 : 0);
  return hundredths > 10000 ? null : hundredths;
}

/// A rate as typed, kept with its sign: 「-2」 is -200, so the write rules
/// can refuse it (D116) rather than take it for no rate. Null where
/// [rateOf] is, past the sign.
int? signedRateOf(String typed) {
  final trimmed = typed.trim();
  if (!trimmed.startsWith('-')) return rateOf(trimmed);
  final rate = rateOf(trimmed.substring(1));
  return rate == null ? null : -rate;
}

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
