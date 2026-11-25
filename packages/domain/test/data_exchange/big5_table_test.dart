import 'package:domain/src/data_exchange/big5_table.dart';
import 'package:test/test.dart';

void main() {
  test('one character per code: 89 lead bytes of 157 trail bytes', () {
    // Lead bytes 0xA1..0xF9 are 89; trail bytes 0x40..0x7E (63) and
    // 0xA1..0xFE (94) are 157: 89 * 157 = 13,973.
    expect(big5Characters.length, 13973);
  });

  test('codes land where cp950 puts them', () {
    int at(int lead, int trail) =>
        (lead - 0xA1) * 157 + (trail < 0x7F ? trail - 0x40 : trail - 0xA1 + 63);
    // A1 40 is the ideographic space; A4 A4 is 中 (3 * 157 + 3 + 63 = 537);
    // A3 E1 is the euro sign; F9 FE is the last code, ▓.
    expect(at(0xA4, 0xA4), 537);
    expect(big5Characters.codeUnitAt(at(0xA1, 0x40)), 0x3000);
    expect(big5Characters[at(0xA4, 0xA4)], '中');
    expect(big5Characters.codeUnitAt(at(0xA3, 0xE1)), 0x20AC);
    expect(big5Characters.codeUnitAt(at(0xF9, 0xFE)), 0x2593);
    // A3 C0 has no character.
    expect(big5Characters.codeUnitAt(at(0xA3, 0xC0)), 0xFFFD);
  });
}
