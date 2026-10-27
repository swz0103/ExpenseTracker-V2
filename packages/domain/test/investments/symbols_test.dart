import 'package:domain/investments.dart';
import 'package:test/test.dart';

void main() {
  test('codes are tidied as the exchanges write them', () {
    expect(tidyStockCode(' 2330.tw '), '2330');
    expect(tidyStockCode('00679b.TWO'), '00679B');
    expect(tidyStockCode('00 50'), '0050');
  });

  test('only codes the exchanges quote are Taiwan symbols', () {
    for (final code in ['2330', '2881A', '0050', '00679B', '00631L']) {
      expect(isTaiwanSymbol(code), isTrue, reason: code);
    }
    for (final code in ['AAPL', '0123', '12345', '']) {
      expect(isTaiwanSymbol(code), isFalse, reason: code);
    }
  });

  test('the kind follows the code', () {
    expect(instrumentKindOf('2330'), InstrumentKind.stock);
    expect(instrumentKindOf('0050'), InstrumentKind.etf);
    expect(instrumentKindOf('00679b'), InstrumentKind.bondEtf);
  });
}
