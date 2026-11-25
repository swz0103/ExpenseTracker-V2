import 'package:domain/data_exchange.dart';
import 'package:test/test.dart';

void main() {
  // 台幣 in UTF-8: E5 8F B0, E5 B9 A3.
  const utf8Bytes = [0xE5, 0x8F, 0xB0, 0xE5, 0xB9, 0xA3];

  String read(List<int> bytes) => switch (readFileText(bytes)) {
    TextRead(:final text) => text,
    TextUnreadable() => '(unreadable)',
  };

  TextEncoding? encoding(List<int> bytes) => switch (readFileText(bytes)) {
    TextRead(:final encoding) => encoding,
    TextUnreadable() => null,
  };

  test('UTF-8, with or without a byte order mark (left out)', () {
    expect(read(utf8Bytes), '台幣');
    expect(read([0xEF, 0xBB, 0xBF, ...utf8Bytes]), '台幣');
    expect(encoding(utf8Bytes), TextEncoding.utf8);
    expect(read(const []), '');
    expect(read('a,b\r\n'.codeUnits), 'a,b\r\n');
  });

  test('Big5 as Excel saves it on a Traditional Chinese system', () {
    // Python's cp950 codec: 日期,類型,金額,備註 CR LF
    // 2026-10-01,支出,120,早餐€ CR LF.
    const bytes = [
      164, 233, 180, 193, 44, 195, 254, 171, 172, 44, 170, 247, 195, 66, 44, //
      179, 198, 181, 249, 13, 10, 50, 48, 50, 54, 45, 49, 48, 45, 48, 49, //
      44, 164, 228, 165, 88, 44, 49, 50, 48, 44, 166, 173, 192, 92, 163, 225,
      13, 10,
    ];
    expect(read(bytes), '日期,類型,金額,備註\r\n2026-10-01,支出,120,早餐€\r\n');
    expect(encoding(bytes), TextEncoding.big5);
    // 台幣金額, and the ideographic space A1 40.
    expect(read(const [165, 120, 185, 244, 170, 247, 195, 66]), '台幣金額');
    expect(read(const [161, 64]), '　');
  });

  test('bytes that are neither are not guessed at', () {
    // A lead byte cut off at the end, a trail byte out of range, a code
    // Big5 leaves to users (81 40) and one it has none for (A3 C0).
    expect(readFileText(const [0xA4]), isA<TextUnreadable>());
    expect(readFileText(const [0xA4, 0x20]), isA<TextUnreadable>());
    expect(readFileText(const [0x81, 0x40]), isA<TextUnreadable>());
    expect(readFileText(const [0xA3, 0xC0]), isA<TextUnreadable>());
    expect(readFileText(const [0x80]), isA<TextUnreadable>());
    // Marked UTF-8 that is not is not read as Big5.
    expect(
      readFileText(const [0xEF, 0xBB, 0xBF, 164, 233]),
      isA<TextUnreadable>(),
    );
  });
}
