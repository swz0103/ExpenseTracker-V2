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

  test('a search key folds width, case, 臺 and spaces (N8)', () {
    expect(searchKey('ＧＯＯＧＬＥ'), 'google');
    expect(searchKey('Goo gle'), 'google');
    expect(searchKey('臺灣'), '台灣');
    expect(searchKey('新臺幣'), '新台幣');
    // The ideographic space and a tab go as a plain one does.
    expect(searchKey('匯入　CSV\t檔'), '匯入csv檔');
    expect(searchKey('ＣＳＶ'), 'csv');
    expect(searchKey('  '), '');
    expect(searchKey(''), '');
  });

  test('a search key leaves out what cannot be seen and reads the Chinese '
      'marks as their ASCII ones (review 39 #6)', () {
    // a, a zero-width space (U+200B), b: two letters, as plainText.
    expect(searchKey('a\u200Bb'), 'ab');
    expect(searchKey('\uFEFF現金\u200E'), '現金');
    // 。 and its half-width ｡ a full stop, 、 and ､ a comma.
    expect(searchKey('v1。2'), 'v1.2');
    expect(searchKey('v1｡2'), 'v1.2');
    expect(searchKey('股票、基金'), '股票,基金');
    expect(searchKey('股票､基金'), '股票,基金');
    // The corner brackets, full and half width, a straight quote.
    expect(searchKey('「發票」『載具』｢QR｣'), '"發票""載具""qr"');
    // The wave dash as the full-width tilde already was.
    expect(searchKey('1〜3'), '1~3');
    expect(searchKey('1～3'), '1~3');
    // Typed and looked through alike: 。 finds a ., a pasted name finds.
    expect(searchKey('匯入。csv'), searchKey('匯入.CSV'));
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

  test('the controls that turn text around are taken out (r13 F4)', () {
    // An override makes 'gpj.exe' show as 'exe.jpg'; a name with it is
    // the name without.
    expect(plainText('現\u202E金'), '現金');
    for (final c in [
      0x202A, 0x202B, 0x202C, 0x202D, 0x202E, //
      0x2066, 0x2067, 0x2068, 0x2069,
      0x2028, 0x2029, 0x00AD, 0x180E,
    ]) {
      expect(plainText('a${String.fromCharCode(c)}b'), 'ab', reason: '$c');
    }
    // U+2065, just before the isolates, is no control: it stays, as do
    // the marks that make letters and the joiner of emoji.
    expect(plainText('a⁥b'), 'a⁥b');
    expect(plainText('é'), 'é');
    expect(plainText('🇹🇼'), '🇹🇼');
    expect(plainText('👨‍👩‍👧'), '👨‍👩‍👧');
  });
}
