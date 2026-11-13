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
}
