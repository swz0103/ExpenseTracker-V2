import 'package:domain/data_exchange.dart';
import 'package:test/test.dart';

void main() {
  test('the NT\$ worth column keeps the name files were written with', () {
    expect(homeAmountColumn, '台幣金額');
    expect(ExchangeColumn.home.name, '台幣金額');
  });

  test('the header: the columns of files written before, in their order, '
      'then those added since', () {
    expect(exchangeHeader, [
      '日期',
      '類型',
      '金額',
      '帳戶',
      '轉入帳戶',
      '分類',
      '商家',
      '標籤',
      '備註',
      '代號',
      '股數',
      '手續費',
      '稅',
      '分期',
      '轉入金額',
      '台幣金額',
      '成本算法',
      '當沖',
      '標記',
      '編號',
      '退款對象',
      '群組',
      '定期',
    ]);
  });

  test('only 日期 and 金額 are required', () {
    expect(
      [
        for (final c in ExchangeColumn.values)
          if (c.required) c.name,
      ],
      ['日期', '金額'],
    );
  });

  group('a file\'s header', () {
    test('finds columns by name, trimmed, the first of two', () {
      final header = ExchangeHeader([' 金額 ', '備註', '日期', '備註']);
      expect(header.missing, isEmpty);
      expect(header.has(ExchangeColumn.kind), isFalse);
      final row = ['120', ' 午餐 ', '2026-10-01', '晚餐'];
      expect(header.cell(row, ExchangeColumn.amount), '120');
      expect(header.cell(row, ExchangeColumn.note), '午餐');
      // No such column, and a row that stops short.
      expect(header.cell(row, ExchangeColumn.kind), '');
      expect(header.cell(['120'], ExchangeColumn.date), '');
    });

    test('names the required columns it lacks', () {
      expect(ExchangeHeader(['備註']).missing, [
        ExchangeColumn.date,
        ExchangeColumn.amount,
      ]);
      expect(ExchangeHeader(['日期']).missing, [ExchangeColumn.amount]);
    });
  });
}
