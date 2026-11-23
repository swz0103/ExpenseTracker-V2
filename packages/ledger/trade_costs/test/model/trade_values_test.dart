import 'package:ledger_trade_costs/model/trade_values.dart';
import 'package:test/test.dart';

void main() {
  Matcher fails(InvestmentError code) => throwsA(
    isA<InvestmentException>().having((error) => error.code, 'code', code),
  );

  test('a share quantity keeps its digits exactly', () {
    final q = ShareQuantity.parse('1000');
    expect(q.coefficient, BigInt.from(1000));
    expect(q.scale, 0);
    expect(q.isWhole, isTrue);
    expect(q.toString(), '1000');
  });

  test('trailing zeros of a fraction are dropped', () {
    // 1.500 is 15 tenths: coefficient 15, scale 1.
    final q = ShareQuantity.parse('1.500');
    expect((q.coefficient, q.scale), (BigInt.from(15), 1));
    expect(q.isWhole, isFalse);
    expect(q, ShareQuantity.parse('1.5'));
    expect(q.hashCode, ShareQuantity.parse('1.5').hashCode);
  });

  test('zero, negative and malformed quantities are refused', () {
    for (final text in ['0', '-1', '1.', '01', 'abc', '1.0000000000001']) {
      expect(
        () => ShareQuantity.parse(text),
        fails(InvestmentError.invalidInput),
        reason: text,
      );
    }
  });

  test('an error names its code', () {
    expect(
      const InvestmentException(InvestmentError.fractionalShares).toString(),
      'InvestmentException(fractionalShares)',
    );
  });

  test('the kinds of trade', () {
    expect(TradeKind.values, [
      TradeKind.buy,
      TradeKind.sell,
      TradeKind.dividend,
      TradeKind.capitalReturn,
    ]);
  });
}
