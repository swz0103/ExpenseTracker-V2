import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

void main() {
  test('names are trimmed and counted in characters', () {
    expect(cleanName('  午餐  '), '午餐');
    expect(cleanName('😀' * 100), '😀' * 100);
    expect(cleanName('😀' * 101), isNull);
    expect(cleanName('a' * 120, max: 120), 'a' * 120);
    for (final bad in ['', '   ', 'a\nb', 'tab\there', '\u007f']) {
      expect(cleanName(bad), isNull, reason: bad);
    }
  });

  test('full-width and case differences compare equal', () {
    expect(nameKey('７－ＥＬＥＶＥＮ'), nameKey('7-eleven'));
    expect(nameKey('全聯　福利中心'), nameKey('全聯 福利中心'));
    expect(nameKey('  Costco   好市多 '), 'costco 好市多');
    expect(nameKey('餐飲'), isNot(nameKey('餐廳')));
  });
}
