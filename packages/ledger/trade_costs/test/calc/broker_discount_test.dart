import 'package:ledger_trade_costs/model/trade_values.dart'
    show InvestmentError, InvestmentException;
import 'package:ledger_trade_costs/calc/broker_discount.dart';
import 'package:ledger_trade_costs/calc/charges.dart';
import 'package:test/test.dart';

int? _read(String text) => switch (readBrokerDiscount(text)) {
  DiscountRead(:final basisPoints) => basisPoints,
  _ => null,
};

void main() {
  test('one range: more than nothing, at most the full fee', () {
    expect(BrokerDiscountRange.lowest, 1);
    expect(BrokerDiscountRange.highest, 10000);
    expect(BrokerDiscountRange.holds(0), isFalse);
    expect(BrokerDiscountRange.holds(1), isTrue);
    expect(BrokerDiscountRange.holds(10000), isTrue);
    expect(BrokerDiscountRange.holds(10001), isFalse);
    expect(BrokerDiscountRange.clamp(0), 1);
    expect(BrokerDiscountRange.clamp(12000), 10000);
    expect(BrokerDiscountRange.clamp(2800), 2800);
  });

  test('a share of the fee, in basis points', () {
    // 0.6 of the fee is 6000 basis points; 0.28 is 2800.
    expect(_read('0.6'), 6000);
    expect(_read('.28'), 2800);
    expect(_read(' 0.285 '), 2850);
    expect(_read('1'), 10000);
    expect(_read('0.0001'), 1);
  });

  test('in 折, as a broker writes it', () {
    // 6折 is 6 × 1000 = 6000; 2.8折 is 2800; 10折 is no discount.
    expect(_read('6折'), 6000);
    expect(_read('2.8 折'), 2800);
    expect(_read('2.85折'), 2850);
    expect(_read('10 折'), 10000);
  });

  test('outside the range, or not a discount', () {
    expect(readBrokerDiscount('0'), isA<DiscountOutOfRange>());
    expect(readBrokerDiscount('0 折'), isA<DiscountOutOfRange>());
    // 6 alone is six times the fee, not 6折.
    expect(readBrokerDiscount('6'), isA<DiscountOutOfRange>());
    expect(readBrokerDiscount('11折'), isA<DiscountOutOfRange>());
    expect(
      readBrokerDiscount('123456789012345678901'),
      isA<DiscountOutOfRange>(),
    );
    expect(readBrokerDiscount(''), isA<DiscountUnreadable>());
    expect(readBrokerDiscount('.'), isA<DiscountUnreadable>());
    expect(readBrokerDiscount('六折'), isA<DiscountUnreadable>());
    expect(readBrokerDiscount('-0.5'), isA<DiscountUnreadable>());
    // Finer than a basis point.
    expect(readBrokerDiscount('0.00005'), isA<DiscountUnreadable>());
    expect(readBrokerDiscount('2.8005折'), isA<DiscountUnreadable>());
  });

  test('a share written in 折 is neither form (D86)', () {
    // 0.6折 would be 600 basis points, a tenth of the 6折 meant.
    expect(readBrokerDiscount('0.6折'), isA<DiscountUnreadable>());
    expect(readBrokerDiscount('.28 折'), isA<DiscountUnreadable>());
    expect(readBrokerDiscount('0.999折'), isA<DiscountUnreadable>());
    // One 折 is 1000; nothing at all stays out of range.
    expect(_read('1折'), 1000);
    expect(readBrokerDiscount('0折'), isA<DiscountOutOfRange>());
  });

  test('full-width digits and point read as typed (D86)', () {
    // ６折 is 6折, 6000; ０．２８ is 0.28, 2800; the ideographic space
    // is ignored.
    expect(_read('６折'), 6000);
    expect(_read('２．８　折'), 2800);
    expect(_read('０．２８'), 2800);
    expect(readBrokerDiscount('０．６折'), isA<DiscountUnreadable>());
    // An Arabic-Indic three is not a digit the app reads.
    expect(readBrokerDiscount('٣折'), isA<DiscountUnreadable>());
  });

  test('the charges are checked against the same range', () {
    expect(
      TaiwanTradeCharges(discountBasisPoints: 10000).discountBasisPoints,
      10000,
    );
    expect(
      () => TaiwanTradeCharges(discountBasisPoints: 10001),
      throwsA(
        isA<InvestmentException>().having(
          (e) => e.code,
          'code',
          InvestmentError.invalidInput,
        ),
      ),
    );
  });
}
