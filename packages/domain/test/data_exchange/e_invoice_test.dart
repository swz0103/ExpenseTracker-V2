import 'package:core/foundation_values.dart';
import 'package:domain/data_exchange.dart';
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
        download(['x,AB1,20261001,店,開立,品,10', 'x,AB2,20261301,店,開立,品,10']),
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

  group('the rows of one invoice (R12 F6)', () {
    test('a void row voids the invoice, whichever row says so', () {
      final file = readEInvoices(
        download(['x,AB1,20261001,店,開立,a,10', 'x,AB1,20261001,店,作廢,b,20']),
      );
      expect(file.invoices, isEmpty);
      expect(file.refused, isEmpty);
    });

    test('rows that disagree on the date or seller leave it out', () {
      final file = readEInvoices(
        download([
          'x,AB1,20261001,店甲,開立,a,10',
          'x,AB1,20271231,店乙,開立,b,20',
          'x,AB2,20261001,店,開立,a,10',
          'x,AB2,20261001,別家,開立,b,20',
          'x,AB3,20261002,店,開立,c,30',
        ]),
      );
      expect([for (final i in file.invoices) i.number], ['AB3']);
      expect(file.refused, [
        (
          number: 'AB1',
          seller: '店甲',
          line: 2,
          why: InvoiceRefusal.rowsDisagree,
        ),
        (number: 'AB2', seller: '店', line: 4, why: InvoiceRefusal.rowsDisagree),
      ]);
      expect(
        parseEInvoices(download(['x,AB3,20261002,店,開立,c,30'])),
        hasLength(1),
      );
    });

    test('an invoice dated before 1950 is left out (D93)', () {
      final file = readEInvoices(download(['x,AB1,19491231,店,開立,a,10']));
      expect(file.invoices, isEmpty);
      expect(file.refused, [
        (number: 'AB1', seller: '店', line: 2, why: InvoiceRefusal.tooEarly),
      ]);
    });

    test('the line named is the line of the file', () {
      // Line 1 the header, 2 and 3 blank, 4 and 5 one record with a line
      // break in its words, 6 the unreadable row.
      expect(
        () => parseEInvoices(
          '$header\n\n\n"a\nb",AB1,20261001,店,開立,a,10\n'
          'x,AB2,bad,店,開立,a,1\n',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith('Line 6:'),
          ),
        ),
      );
    });
  });

  group('M and D lines, by the same reader', () {
    test('each M line an invoice, its D lines its items, oldest first', () {
      final file = readInvoiceFile(
        'M|手機條碼|/A|20261004|1|乙店|AB00000002|900|開立\n'
        'M|手機條碼|/A|20261003|1|甲店|AB00000001|268|開立\n'
        'D|AB00000001|199|鮮奶\n'
        'D|AB00000001|69|吐司\n',
      );
      expect(
        [for (final i in file.invoices) i.number],
        ['AB00000001', 'AB00000002'],
      );
      final first = file.invoices.first;
      expect(first.date, BusinessDate(2026, 10, 3));
      expect((first.seller, first.line), ('甲店', 2));
      expect(first.amount, ntd(268));
      expect(first.items, ['鮮奶', '吐司']);
      expect(file.refused, isEmpty);
    });

    test('a line that cannot be booked is left out, named; the rest read', () {
      final file = readInvoiceLines(
        'M|x|y|20261340|1|甲|AB1|10|開立\n'
        'M|x|y|261003|1|甲|AB2|10|開立\n'
        'M|x|y|20261003|1|甲|AB3|.5|開立\n'
        'M|x|y|20261003|1|甲|AB4|10|作廢\n'
        'M|x|y|20261003|1|甲|AB5|10|開立\n'
        'M|x|y|20261003|1|甲|AB5|10|開立\n'
        'M|x|y|20261012|1|甲||10|開立\n',
        latest: BusinessDate(2026, 10, 11),
      );
      expect([for (final i in file.invoices) i.number], ['AB5']);
      expect(
        [for (final r in file.refused) (r.number, r.line, r.why)],
        [
          ('AB1', 1, InvoiceRefusal.unreadableDay),
          ('AB2', 2, InvoiceRefusal.shortYear),
          ('AB3', 3, InvoiceRefusal.badAmount),
          ('AB4', 4, InvoiceRefusal.voided),
          ('AB5', 6, InvoiceRefusal.repeated),
          ('', 7, InvoiceRefusal.tooLate),
        ],
      );
      expect(file.refused.last.seller, '甲');
    });

    test('the consumption CSV goes to its own reading', () {
      final file = readInvoiceFile(download(['x,AB1,20261001,店,開立,品,10']));
      expect(file.invoices.single.line, 2);
    });
  });
}
