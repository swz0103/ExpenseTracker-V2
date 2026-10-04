import 'dart:math';

import '../theme.dart';
import 'chart_data.dart';

/// A year of made-up spending for the preview, ending on the given day.
/// The same date always gives the same numbers.
ChartData demoCharts(int year, int month, int day, {int count = 12}) {
  final random = Random(year * 100 + month);
  final months = <MonthPoint>[];
  final categories = <List<CategorySlice>>[];
  final days = <List<int>>[];
  var netWorth = 380000;
  for (var back = count - 1; back >= 0; back--) {
    final first = DateTime.utc(year, month - back);
    final length = DateTime.utc(first.year, first.month + 1, 0).day;
    final current = back == 0;
    final share = current ? day / length : 1.0;
    final slices = _categories(random, first.month, share);
    final expense = slices.fold(0, (sum, slice) => sum + slice.amount);
    var income = current && day < 5 ? 0 : 52000 + random.nextInt(3000);
    if (first.month == 2) income += 78000;
    netWorth += income - expense;
    months.add(
      MonthPoint(
        first.year,
        first.month,
        income: income,
        expense: expense,
        netWorth: netWorth,
      ),
    );
    categories.add(slices);
    days.add(_spread(random, expense, current ? day : length, first));
  }
  return ChartData(months: months, categories: categories, days: days);
}

const _rent = 12000;

/// The demo's category colours, also used by the home screen's entries.
final demoCategoryColors = {
  '居家': Palette.series[0],
  '餐飲': Palette.series[1],
  '交通': Palette.series[2],
  '娛樂': Palette.series[3],
  '購物': Palette.series[4],
  '醫療': Palette.series[5],
};

/// Typical monthly amounts, varied a little each month.
const _plan = [
  ('餐飲', '早餐', 1800),
  ('餐飲', '午餐', 4200),
  ('餐飲', '晚餐', 4800),
  ('餐飲', '飲料', 1200),
  ('居家', '房租', _rent),
  ('居家', '水電', 1400),
  ('居家', '網路', 699),
  ('交通', '捷運', 1280),
  ('交通', '油資', 1500),
  ('交通', '計程車', 600),
  ('購物', '日用品', 1500),
  ('購物', '衣物', 1800),
  ('購物', '3C', 2000),
  ('娛樂', '電影', 600),
  ('娛樂', '旅遊', 3000),
  ('娛樂', '訂閱', 450),
  ('醫療', '門診', 400),
  ('醫療', '藥品', 300),
];

List<CategorySlice> _categories(Random random, int month, double share) {
  final children = <String, List<CategorySlice>>{};
  for (final (category, item, typical) in _plan) {
    var amount = (typical * (0.5 + random.nextDouble())).round();
    if (item == '旅遊') {
      amount = random.nextDouble() < 0.25 ? 12000 + random.nextInt(9000) : 0;
    }
    if (month == 12 && item == '衣物') amount *= 3;
    // Rent is paid in full on the 1st, even early in the month.
    amount = typical == _rent ? _rent : (amount * share).round();
    if (amount > 0) {
      final color = demoCategoryColors[category]!;
      (children[category] ??= []).add(CategorySlice(item, amount, color));
    }
  }
  final result = [
    for (final MapEntry(key: name, value: items) in children.entries)
      CategorySlice(
        name,
        items.fold(0, (sum, item) => sum + item.amount),
        demoCategoryColors[name]!,
        children: items..sort((a, b) => b.amount.compareTo(a.amount)),
      ),
  ];
  result.sort((a, b) => b.amount.compareTo(a.amount));
  return result;
}

/// [total] over [count] days: rent on the 1st, the rest more on weekends.
List<int> _spread(Random random, int total, int count, DateTime first) {
  if (count == 0) return const [];
  double weight(int day) {
    final weekday = DateTime.utc(first.year, first.month, day).weekday;
    final weekend = weekday >= DateTime.saturday ? 1.6 : 1.0;
    return (0.3 + random.nextDouble()) * weekend;
  }

  final weights = [for (var day = 1; day <= count; day++) weight(day)];
  final sum = weights.fold(0.0, (a, b) => a + b);
  final rest = max(0, total - _rent);
  final result = [for (final w in weights) (rest * w / sum).floor()];
  result[count - 1] += rest - result.fold(0, (a, b) => a + b);
  result[0] += total - rest;
  return result;
}
