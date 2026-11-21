import 'package:domain/data_exchange.dart';
import 'package:test/test.dart';

void main() {
  test('words a spreadsheet would run as a formula are kept as words, '
      'and read back unchanged', () {
    const row = [
      '=HYPERLINK("http://x","click")',
      '+1+2',
      '@SUM(A1)',
      '-x',
      "'=already",
      "'plain",
      '-120',
      '3.5',
      'tab\there',
      '',
    ];
    final text = writeCsv([row]);
    expect(text, contains("'=HYPERLINK"));
    expect(text, contains("'+1+2"));
    expect(text, contains("''=already"));
    expect(text, contains(',-120,'));
    expect(text, contains(",'plain,"));
    expect(readCsv(text), [row]);
  });

  test('a quote inside a field is part of the words', () {
    expect(readCsv('5",a"b\n'), [
      ['5"', 'a"b'],
    ]);
    expect(readCsv('"a""b",c\r\n'), [
      ['a"b', 'c'],
    ]);
  });

  test('words after a closing quote are refused, naming the line', () {
    expect(
      () => readCsv('日期,金額\n2026-10-01,"12"3\n'),
      throwsA(
        isA<CsvFormatException>()
            .having((e) => e.line, 'line', 2)
            .having((e) => e.unclosed, 'unclosed', isFalse),
      ),
    );
  });

  test('a quote never closed names the line it opened on', () {
    expect(
      () => readCsv('a\nb,"c\nd\n'),
      throwsA(
        isA<CsvFormatException>()
            .having((e) => e.line, 'line', 2)
            .having((e) => e.unclosed, 'unclosed', isTrue),
      ),
    );
  });
}
