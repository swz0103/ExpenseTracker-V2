import 'package:core/percent/percent.dart';
import 'package:test/test.dart';

void main() {
  test('divideRounded: half away from zero', () {
    // 7 / 2 = 3.5 -> 4; -7 / 2 = -3.5 -> -4; 10 / 3 = 3.33 -> 3.
    expect(divideRounded(7, 2), 4);
    expect(divideRounded(-7, 2), -4);
    expect(divideRounded(7, -2), -4);
    expect(divideRounded(10, 3), 3);
    expect(divideRounded(0, 5), 0);
    expect(() => divideRounded(1, 0), throwsArgumentError);
  });

  test('percent: a whole percent', () {
    // 1 / 3 = 33.3% -> 33; 1 / 8 = 12.5% -> 13; 2 / 3 = 66.7% -> 67.
    expect(percent(1, 3), 33);
    expect(percent(1, 8), 13);
    expect(percent(2, 3), 67);
    // 50,174 / 50,000 = 100.348% -> 100.
    expect(percent(50174, 50000), 100);
    expect(percent(5, 0), 0);
  });

  test('percentTenths: one decimal', () {
    // 9 / 1000 = 0.9% -> 9 tenths, not truncated to 0.
    expect(percentTenths(9, 1000), 9);
    // 1 / 3 = 33.33% -> 333; -1 / 8 = -12.5% -> -125.
    expect(percentTenths(1, 3), 333);
    expect(percentTenths(-1, 8), -125);
    // 1 / 16 = 6.25% -> 63 (6.3%), half away from zero.
    expect(percentTenths(1, 16), 63);
    expect(percentTenths(1, 0), 0);
  });

  test('ratioTenths: a ratio held as a double', () {
    // 0.1234 = 12.34% -> 123; 0.0125 = 1.25% -> 13; -0.00949 -> -0.9%.
    expect(ratioTenths(0.1234), 123);
    expect(ratioTenths(0.0125), 13);
    expect(ratioTenths(-0.00949), -9);
    expect(ratioTenths(0), 0);
  });

  test('isOver compares the amounts, not a rounded percent', () {
    // 50,174 of 50,000 rounds to 100% but is over.
    expect(isOver(50174, 50000), isTrue);
    expect(isOver(50000, 50000), isFalse);
    expect(isOver(49999, 50000), isFalse);
  });
}
