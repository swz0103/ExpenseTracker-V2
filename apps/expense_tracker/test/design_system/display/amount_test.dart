import 'package:expense_tracker/design_system/display/amount.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('amounts are written in their own currency', () {
    expect(amountIn(1234567, 'TWD'), '1,234,567');
    expect(amountIn(123450, 'USD'), 'USD 1,234.50');
    expect(amountIn(-5, 'USD'), 'USD -0.05');
    expect(amountIn(5000, 'JPY'), 'JPY 5,000');
    expect(plainIn(123450, 'USD'), '1234.50');
    expect(plainIn(-123450, 'USD'), '-1234.50');
    expect(plainIn(300, 'TWD'), '300');
  });

  test('beside its currency, an amount shows its figures only', () {
    // A foreign amount once read 「USD USD 12.50」 on the forms.
    expect(currencyLabel('TWD'), r'NT$');
    expect(currencyLabel('USD'), 'USD');
    expect(figuresIn(123450, 'USD'), '1,234.50');
    expect(figuresIn(-5, 'USD'), '-0.05');
    expect(figuresIn(5000, 'JPY'), '5,000');
    expect(figuresIn(1234567, 'TWD'), '1,234,567');
  });

  test('signed and spent amounts carry a true minus sign', () {
    expect(signed(1200), '+1,200');
    expect(signed(-80), '−80');
    expect(signed(0), '0');
    expect(spent(200), '−200');
  });

  test('short amounts in 萬, rounded half away from zero', () {
    // 52,000 / 10,000 = 5.2.
    expect(tenThousands(52000), '5.2');
    // 12,350 / 10,000 = 1.235 -> 1.2 (the hundredths do not count).
    expect(tenThousands(12350), '1.2');
    // 125,000 / 10,000 = 12.5; 1,250,000 / 10,000 = 125.
    expect(shortAmount(125000), '12.5萬');
    expect(shortAmount(1250000), '125萬');
    expect(shortAmount(8500), '8,500');
    expect(shortAmount(-125000), '-12.5萬');
  });

  test('F06: counts are grouped like amounts', () {
    expect(countOf(8177, CountUnit.entries), '8,177 筆');
    expect(countOf(21000, CountUnit.shares), '21,000 股');
    expect(countOf(1780, CountUnit.days), '1,780 天');
    expect(countOf(12, CountUnit.periods), '12 期');
  });

  test('INV-03: a share price keeps its real ticks', () {
    // 128.5 is a real tick for prices of 100 to 500; once shown as 129.
    expect(stockPrice(128.5), '128.5');
    expect(stockPrice(1045), '1,045');
    expect(stockPrice(23.45), '23.45');
    expect(stockPrice(600.0), '600');
    expect(plainPrice(1045.5), '1045.5');
    expect(priceMove(-0.5), '0.50');
    expect(priceMove(12), '12.00');
  });

  group('RPT-06: percentages, one rounding', () {
    test('signed with one decimal', () {
      // 9 / 1,000 = 0.9%, once shown as 0% by a truncation.
      expect(percentOf(9, 1000), '+0.9%');
      // 1 / 16 = 6.25% -> 6.3%; -1 / 8 = -12.5%.
      expect(percentOf(1, 16), '+6.3%');
      expect(percentOf(-1, 8), '-12.5%');
      expect(percentOf(0, 8), '0.0%');
      expect(percentOf(5, 0), '0%');
    });
    test('a ratio held as a double', () {
      expect(ratioPercent(0.125), '+12.5%');
      expect(ratioPercent(-0.04), '-4.0%');
    });
    test('whole percent rounds half away from zero', () {
      // 1 / 8 = 12.5% -> 13%; truncated it was 12%.
      expect(wholePercent(1, 8), '13%');
      expect(wholePercent(1, 0), '0%');
      expect(tenthsPercent(125), '12.5%');
      expect(tenthsPercent(125, sign: true), '+12.5%');
    });
  });

  group('F107: amounts read aloud with their direction in words', () {
    test('spending and income', () {
      expect(spokenAmount(1844, sense: AmountSense.spending), '支出 1,844 元');
      expect(spokenAmount(25000, sense: AmountSense.income), '收入 25,000 元');
      // D9: a refund gives spending back; it is not read as income.
      expect(spokenAmount(300, sense: AmountSense.refund), '退款 300 元');
      expect(shownAmount(300, sense: AmountSense.refund), '+300');
      // Only the size counts for a direction.
      expect(spokenAmount(-1844, sense: AmountSense.spending), '支出 1,844 元');
    });
    test('foreign currencies by their names', () {
      expect(spokenAmount(1250, currency: 'USD'), '美元 12.50');
      expect(
        spokenAmount(300, currency: 'JPY', sense: AmountSense.spending),
        '支出 日圓 300',
      );
      expect(spokenAmount(5, currency: 'XYZ'), 'XYZ 0.05');
    });
    test('rises and falls', () {
      expect(spokenAmount(1200, sense: AmountSense.signed), '正 1,200 元');
      expect(spokenAmount(-80, sense: AmountSense.signed), '負 80 元');
      expect(spokenAmount(0, sense: AmountSense.signed), '0 元');
      expect(spokenAmount(-300), '負 300 元');
      expect(spokenAmount(300), '300 元');
    });
    test('hidden amounts are not read out', () {
      expect(
        spokenAmount(1844, sense: AmountSense.spending, hidden: true),
        '支出 金額已隱藏',
      );
    });
    test('what is shown beside it', () {
      expect(shownAmount(1844, sense: AmountSense.spending), '−1,844');
      expect(shownAmount(25000, sense: AmountSense.income), '+25,000');
      expect(shownAmount(300, currency: 'USD'), 'USD 3.00');
      expect(shownAmount(-300, sense: AmountSense.signed), '−300');
      expect(shownAmount(-300), '-300');
      expect(shownAmount(1, hidden: true), '••••');
    });
  });
}
