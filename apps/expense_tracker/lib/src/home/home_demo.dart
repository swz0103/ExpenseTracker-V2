import 'dart:math';

import '../charts/chart_data.dart';
import '../charts/demo_charts.dart';
import '../theme.dart';
import 'home_data.dart';

/// The home screen's made-up data, matching [charts] (see [demoCharts]).
HomeData demoHome(ChartData charts, int year, int month, int day) {
  final today = DateTime.utc(year, month, day);
  final count = charts.months.length;
  final last = {
    for (final slice in charts.categories[count - 2]) slice.name: slice.amount,
  };
  int spentOn(DateTime date) {
    final back = (today.year - date.year) * 12 + today.month - date.month;
    return charts.days[count - 1 - back][date.day - 1];
  }

  final week = [
    for (var back = 6; back >= 0; back--)
      _day(DateTime.utc(year, month, day - back), spentOn),
  ];
  return HomeData(
    today: today,
    month: charts.months.last,
    budget: 40000,
    days: charts.days.last,
    categories: charts.categories.last,
    lastMonth: last,
    holdings: _holdings,
    week: week,
  );
}

final _holdings = [
  Holding(
    '台積電',
    '2330',
    value: 412000,
    cost: 268000,
    change: 6200,
    color: Palette.series[0],
  ),
  Holding(
    '元大台灣50',
    '0050',
    value: 286500,
    cost: 231000,
    change: 2150,
    color: Palette.series[1],
  ),
  Holding(
    '國泰永續高股息',
    '00878',
    value: 158400,
    cost: 150200,
    change: -320,
    color: Palette.series[2],
  ),
  Holding(
    '元大高股息',
    '0056',
    value: 96800,
    cost: 88300,
    change: -150,
    color: Palette.series[3],
  ),
  Holding(
    '中華電',
    '2412',
    value: 61500,
    cost: 58800,
    change: 100,
    color: Palette.series[5],
  ),
];

/// Everyday entries the demo picks from: category, title, place.
const _usual = [
  ('餐飲', '早餐', '美而美'),
  ('餐飲', '午餐', '八方雲集'),
  ('餐飲', '晚餐', '鼎泰豐'),
  ('餐飲', '咖啡', '路易莎'),
  ('交通', '捷運', '台北捷運'),
  ('交通', '加油', '中油'),
  ('購物', '日用品', '全聯'),
  ('購物', '生活用品', '無印良品'),
  ('娛樂', '電影', '威秀影城'),
  ('娛樂', '訂閱', 'Spotify'),
  ('醫療', '藥品', '屈臣氏'),
];

const _accounts = ['現金', '玉山信用卡', '悠遊卡'];

DayEntries _day(DateTime date, int Function(DateTime) spentOn) {
  final random = Random(date.year * 10000 + date.month * 100 + date.day);
  var rest = spentOn(date);
  final entries = <Entry>[];
  if (date.day == 1 && rest >= 12000) {
    entries.add(
      Entry(
        '房租',
        12000,
        category: '居家',
        account: '薪轉戶',
        color: demoCategoryColors['居家']!,
        place: '房東',
      ),
    );
    rest -= 12000;
  }
  final parts = rest < 200 ? 1 : 1 + random.nextInt(4);
  final weights = [for (var i = 0; i < parts; i++) 0.3 + random.nextDouble()];
  final sum = weights.fold(0.0, (a, b) => a + b);
  var left = rest;
  for (final (i, weight) in weights.indexed) {
    final amount = i == parts - 1 ? left : (rest * weight / sum).floor();
    left -= amount;
    if (amount <= 0) continue;
    final (category, title, place) = _usual[random.nextInt(_usual.length)];
    entries.add(
      Entry(
        title,
        amount,
        category: category,
        account: _accounts[random.nextInt(_accounts.length)],
        color: demoCategoryColors[category]!,
        place: place,
      ),
    );
  }
  return DayEntries(date, entries);
}
