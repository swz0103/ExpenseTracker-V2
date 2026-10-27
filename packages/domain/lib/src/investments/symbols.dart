import 'values.dart';

/// The codes TWSE and TPEx quote: ordinary and preferred shares (2330,
/// 2881A) and ETFs, bond, leveraged and inverse ones included (0050,
/// 00679B, 00631L).
final _taiwanSymbol = RegExp(r'^(?:[1-9][0-9]{3}|00[0-9]{2,4})[A-Z]?$');

/// [code] as the exchanges write it: no spaces, upper case, without a
/// `.TW` or `.TWO` ending.
String tidyStockCode(String code) => code
    .trim()
    .toUpperCase()
    .replaceAll(RegExp(r'\s+'), '')
    .replaceFirst(RegExp(r'\.TWO?$'), '');

/// Whether the exchanges quote [code].
bool isTaiwanSymbol(String code) => _taiwanSymbol.hasMatch(code);

/// What [code] is, for its securities tax: codes starting with 00 are
/// ETFs, and those ending in B bond ETFs.
InstrumentKind instrumentKindOf(String code) {
  final tidy = tidyStockCode(code);
  if (!tidy.startsWith('00')) return InstrumentKind.stock;
  return tidy.endsWith('B') ? InstrumentKind.bondEtf : InstrumentKind.etf;
}
