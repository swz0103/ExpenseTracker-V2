import 'package:core/money/typed_text.dart';
import 'package:test/test.dart';

void main() {
  test('full-width forms read as ASCII; the rest stays', () {
    expect(halfWidth('１２．５'), '12.5');
    expect(halfWidth('６折'), '6折');
    expect(halfWidth('－３，０００'), '-3,000');
    expect(halfWidth('　７　'), ' 7 ');
    expect(halfWidth('六折 0.6'), '六折 0.6');
    expect(halfWidth(''), '');
  });

  test('outside words lose what cannot be seen (R12)', () {
    expect(plainText('a\u0000b'), 'ab');
    expect(plainText('現金​'), '現金');
    expect(plainText('﻿‎全聯‏⁠'), '全聯');
    expect(plainText('a\u0007\u001Fb\u007F\u0085c'), 'abc');
    expect(plainText('a\uD800b'), 'ab');
    expect(plainText('兩\r\n行\t'), '兩\r\n行\t');
    // A family emoji keeps its joiner; a pair of surrogates stays.
    expect(plainText('👨‍👩'), '👨‍👩');
    expect(plainText('😀'), '😀');
    expect(plainText(''), '');
  });
}
