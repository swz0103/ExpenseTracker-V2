import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:core/money/amount_parser.dart';
import 'package:domain/data_exchange.dart';
import 'package:test/test.dart';

void main() {
  test('a day is written as 2026-03-05 and read by the import rule', () {
    const cell = DayCell();
    expect(cell.write(BusinessDate(2026, 3, 5)), '2026-03-05');
    expect((cell.read('115/3/5') as DayRead).date, BusinessDate(2026, 3, 5));
    expect(
      (cell.read(
        '2026-10-02',
        latest: BusinessDate(2026, 10, 1),
      ) as DayRefused).problem,
      DayProblem.tooLate,
    );
  });

  group('amounts', () {
    const cell = AmountCell();
    test('in the currency\'s smallest unit, NT\$ and commas read', () {
      expect(cell.read('1,200', 'TWD').minorOrNull, 1200);
      expect(cell.read('NT\$ 85', 'TWD').minorOrNull, 85);
      expect(cell.read('-NT\$5', 'TWD').minorOrNull, -5);
      // 12.5 dollars is 1250 cents.
      expect(cell.read('12.5', 'USD').minorOrNull, 1250);
    });
    test('what could be read two ways is refused, empty is empty', () {
      expect(
        (cell.read('1.234,50', 'TWD') as AmountRefused).problem,
        AmountProblem.ambiguous,
      );
      expect(
        (cell.read('', 'TWD') as AmountRefused).problem,
        AmountProblem.empty,
      );
    });
    test('written as typed into a field', () {
      expect(cell.write(123450, 'USD'), '1234.50');
      expect(cell.write(300, 'TWD'), '300');
      expect(cell.write(null, 'TWD'), '');
    });
  });

  test('counts: empty for 0, commas read, words refused', () {
    const cell = CountCell();
    expect(cell.write(0), '');
    expect(cell.write(1000), '1000');
    expect(cell.read(''), 0);
    expect(cell.read('1,000'), 1000);
    expect(cell.read('很多'), isNull);
  });

  test('flags: 是 or empty; other words say neither', () {
    const cell = FlagCell();
    expect(cell.write(true), '是');
    expect(cell.write(false), '');
    expect(cell.read('是'), isTrue);
    expect(cell.read('TRUE'), isTrue);
    expect(cell.read(''), isFalse);
    expect(cell.read('否'), isFalse);
    expect(cell.read('也許'), isNull);
  });

  test('tags: split at 、 or ; when there, else at spaces', () {
    const cell = TagsCell();
    expect(cell.write(['家用', '早餐']), '家用、早餐');
    // One tag with a space is read back whole.
    expect(cell.write(['出差 台北']), '出差 台北、');
    expect(cell.read('出差 台北、'), ['出差 台北']);
    expect(cell.read('家用、早餐'), ['家用', '早餐']);
    expect(cell.read('出差 台北;家用'), ['出差 台北', '家用']);
    expect(cell.read('家用 早餐'), ['家用', '早餐']);
    expect(cell.read(''), isEmpty);
  });

  group('categories', () {
    const cell = CategoryCell();
    test('a split is written and read as name=amount parts', () {
      expect(
        cell.write('飲食', const [('飲食', 200), ('居家', 100)], 'TWD'),
        '飲食=200;居家=100',
      );
      expect(cell.write('飲食', const [], 'TWD'), '飲食');
      final read = cell.read('飲食=200;居家=100', 'TWD') as SplitCategory;
      expect(read.parts, [('飲食', 200), ('居家', 100)]);
    });
    test('a name with an = is a name; one part is a name as written', () {
      expect((cell.read('A=B', 'TWD') as OneCategory).name, 'A=B');
      expect((cell.read('飲食=200', 'TWD') as OneCategory).name, '飲食=200');
      expect(
        (cell.read('飲食=200;居家=100', 'TWD', split: false) as OneCategory).name,
        '飲食=200;居家=100',
      );
    });
    test('a part of no amount is refused', () {
      expect(cell.read('飲食=0;居家=100', 'TWD'), isA<SplitUnreadable>());
    });
  });

  test('kinds: written by their word, read by others too', () {
    const cell = KindCell();
    expect(
      [for (final k in LineKind.values) cell.write(k)],
      ['支出', '收入', '轉帳', '買進', '賣出', '股息', '配股', '分割', '減資', '退款'],
    );
    expect((cell.read('買入') as KindNamed).kind, LineKind.buy);
    expect((cell.read('Expense') as KindNamed).kind, LineKind.expense);
    expect((cell.read('現金股利') as KindNamed).kind, LineKind.cash);
    expect((cell.read('') as KindNamed).kind, isNull);
    expect((cell.read('魔法') as KindUnknown).words, '魔法');
  });

  test('marks (D52): 回饋, 年費, 發票 or none', () {
    const cell = MarkCell();
    expect(
      [for (final m in LineMark.values) cell.write(m)],
      ['回饋', '年費', '發票'],
    );
    expect(cell.write(null), '');
    for (final mark in LineMark.values) {
      expect((cell.read(mark.word) as MarkNamed).mark, mark);
    }
    expect((cell.read('') as MarkNamed).mark, isNull);
    expect((cell.read('紅利') as MarkUnknown).words, '紅利');
  });

  test('costing: 平均成本 for the average price', () {
    const cell = CostCell();
    expect(cell.write(average: true), '平均成本');
    expect(cell.write(average: false), '');
    expect(cell.read('平均成本'), isTrue);
    expect(cell.read('平均'), isTrue);
    expect(cell.read(''), isFalse);
  });

  test('words are kept as they are', () {
    const cell = TextCell();
    expect(cell.read('午餐'), '午餐');
    expect(cell.write(null), '');
    expect(cell.write('g-1'), 'g-1');
  });
}
