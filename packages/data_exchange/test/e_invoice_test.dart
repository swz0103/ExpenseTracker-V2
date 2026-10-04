import 'package:data_exchange/data_exchange.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:test/test.dart';

/// Columns in a different order from the platform's download, to show
/// they are found by header.
const header = '載具名稱,發票號碼,發票日期,賣方名稱,發票狀態,消費明細_品名,消費明細_金額';

String download(List<String> rows) =>
    '\u{FEFF}${[header, ...rows].join('\r\n')}\r\n';

void main() {
  final twd = Currency.of('TWD');
  Money ntd(int units) => Money(twd, BigInt.from(units));

  test('line items add up per invoice; voided ones are left out', () {
    final invoices = parseEInvoices(
      download([
        '手機條碼,AB00000002,20261003,全家便利商店,開立,"拿鐵, 大杯",65',
        '手機條碼,AB00000002,20261003,全家便利商店,開立,御飯糰,39',
        '手機條碼,AB00000002,20261003,全家便利商店,開立,御飯糰,39',
        '手機條碼,AB00000001,20261001,誠品,開立,書,380.5',
        '手機條碼,AB00000001,20261001,誠品,開立,書套,19.5',
        '手機條碼,AB00000003,20261002,某超市,作廢,牛奶,95',
      ]),
    );
    expect([for (final i in invoices) i.number], ['AB00000001', 'AB00000002']);
    final books = invoices.first;
    expect(books.date, BusinessDate(2026, 10, 1));
    expect(books.seller, '誠品');
    expect(books.amount, ntd(400));
    expect(books.items, ['書', '書套']);
    final store = invoices.last;
    expect(store.amount, ntd(143));
    expect(store.items, ['拿鐵, 大杯', '御飯糰']);
  });

  test('a row that cannot be read names its line', () {
    Matcher line(int number) => throwsA(
      isA<FormatException>().having(
        (e) => e.message,
        'message',
        startsWith('Line $number:'),
      ),
    );
    expect(
      () => parseEInvoices(download(['x,AB1,2026/10/1,店,開立,品,10'])),
      line(2),
    );
    expect(
      () => parseEInvoices(
        download([
          'x,AB1,20261001,店,開立,品,10',
          'x,AB2,20261301,店,開立,品,10',
        ]),
      ),
      line(3),
    );
    expect(
      () => parseEInvoices(download(['x,AB1,20261001,店,開立,品,1e3'])),
      line(2),
    );
    expect(
      () => parseEInvoices('發票號碼,消費明細_金額\r\nAB1,10'),
      throwsFormatException,
    );
    expect(parseEInvoices(''), isEmpty);
  });

  test('CSV quoting survives a round trip', () {
    final rows = [
      ['日期', '備註'],
      ['2026-10-03', '午餐, 和同事'],
      ['2026-10-04', '他說 "好"'],
      ['2026-10-05', '兩行\r\n備註'],
    ];
    final text = writeCsv(rows);
    expect(text, startsWith('\u{FEFF}日期,備註\r\n'));
    expect(readCsv(text), rows);
    expect(() => readCsv('"open'), throwsFormatException);
  });
}
