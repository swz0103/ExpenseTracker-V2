import 'package:market/market_data.dart';
import 'package:test/test.dart';

/// The month reports a holding's chart reads, in the shapes TWSE and TPEx
/// answered with on 2026-11-13.
void main() {
  test('TWSE month report: every trading day\'s close', () {
    final closes = monthReportCloses({
      'stat': 'OK',
      'fields': [
        '日期',
        '成交股數',
        '成交金額',
        '開盤價',
        '最高價',
        '最低價',
        '收盤價',
        '漲跌價差',
        '成交筆數',
        '註記',
      ],
      'data': [
        [
          '115/11/02',
          '41,165,068',
          '95,950,896,264',
          '2,310.00',
          '2,345.00',
          '2,310.00',
          '2,330.00',
          '-40.00',
          '298,087',
          '',
        ],
        [
          '115/11/03',
          '46,137,336',
          '106,329,297,685',
          '2,320.00',
          '2,330.00',
          '2,290.00',
          '2,300.00',
          '-30.00',
          '300,000',
          '',
        ],
      ],
    });
    expect(closes, hasLength(2));
    expect(closes.first.decimalPrice, '2330.00');
    expect(
      (closes.last.date.year, closes.last.date.month, closes.last.date.day),
      (2026, 11, 3),
    );
  });

  test('TPEx month report: the table under tables, columns with spaces', () {
    final closes = monthReportCloses({
      'stat': 'ok',
      'tables': [
        {
          'fields': ['日 期', '成交張數', '成交仟元', '開盤', '最高', '最低', '收盤', '漲跌', '筆數'],
          'data': [
            [
              '115/11/02',
              '10,402',
              '7,831,069',
              '740.00',
              '770.00',
              '731.00',
              '760.00',
              '4.00',
              '22,796',
            ],
          ],
        },
      ],
    });
    expect(closes.single.decimalPrice, '760.00');
  });

  test('no such stock, or a report that is not one', () {
    expect(
      monthReportCloses({
        'stat': 'ok',
        'tables': [
          {
            'fields': ['日 期', '收盤'],
            'data': [],
          },
        ],
      }),
      isEmpty,
    );
    expect(monthReportCloses({'stat': '很抱歉，沒有符合條件的資料!'}), isEmpty);
    expect(() => monthReportCloses('<html>'), throwsFormatException);
  });
}
