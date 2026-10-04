import 'dart:math';

import 'book.dart';
import 'charts/chart_data.dart';

/// The preview's made-up book, matching [charts] day by day: this month
/// so far and the whole of last month.
Book demoBook(ChartData charts, int year, int month, int day) {
  final today = DateTime.utc(year, month, day);
  final days = <DateTime, List<Entry>>{};
  final count = charts.months.length;
  for (final back in const [1, 0]) {
    final spent = charts.days[count - 1 - back];
    final income = charts.months[count - 1 - back].income;
    for (final (i, amount) in spent.indexed) {
      final date = DateTime.utc(year, month - back, i + 1);
      days[date] = [
        ..._expenses(date, amount),
        if (i == 0)
          Entry(
            '薪資',
            income,
            kind: EntryKind.income,
            category: '薪資',
            account: '薪轉戶',
            place: '公司',
          ),
        if (i == 1)
          const Entry(
            '轉入證券戶',
            10000,
            kind: EntryKind.transfer,
            category: '轉帳',
            account: '薪轉戶',
            toAccount: '證券戶',
          ),
      ];
    }
  }
  final value = _holdings.fold(0, (sum, h) => sum + h.value);
  // The chart demo's net worth, moved so this month ends on the accounts.
  final worth = _accounts.fold(value, (sum, a) => sum + a.balance);
  final shift = worth - charts.months.last.netWorth;
  final history = [
    for (final m in charts.months)
      MonthPoint(
        m.year,
        m.month,
        income: m.income,
        expense: m.expense,
        netWorth: m.netWorth + shift,
      ),
  ];
  return Book(
    today: today,
    budget: 40000,
    days: days,
    accounts: _accounts,
    holdings: _holdings,
    investHistory: _walk(value, 60, year * 100 + month),
    reminders: ['玉山信用卡帳單 $month/15 待繳', '定期：Spotify $month/10'],
    history: history,
  );
}

const _accounts = [
  AccountLine('現金', '現金', 3240),
  AccountLine('薪轉戶', '銀行', 156800),
  AccountLine('玉山信用卡', '信用卡', -8420),
  AccountLine('悠遊卡', '電子票證', 512),
  AccountLine('證券戶', '證券', 67320),
];

const _holdings = [
  Holding('台積電', '2330', value: 412000, cost: 268000, change: 6200),
  Holding('元大台灣50', '0050', value: 286500, cost: 231000, change: 2150),
  Holding('國泰永續高股息', '00878', value: 158400, cost: 150200, change: -320),
  Holding('元大高股息', '0056', value: 96800, cost: 88300, change: -150),
  Holding('中華電', '2412', value: 61500, cost: 58800, change: 100),
];

/// Everyday spending the demo picks from: category, title, place.
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

const _wallets = ['現金', '玉山信用卡', '悠遊卡'];

/// [total] for [date] as a few entries, rent first on the 1st.
List<Entry> _expenses(DateTime date, int total) {
  final random = Random(date.year * 10000 + date.month * 100 + date.day);
  var rest = total;
  final entries = <Entry>[];
  if (date.day == 1 && rest >= 12000) {
    entries.add(
      const Entry(
        '房租',
        12000,
        kind: EntryKind.expense,
        category: '居家',
        account: '薪轉戶',
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
        kind: EntryKind.expense,
        category: category,
        account: _wallets[random.nextInt(_wallets.length)],
        place: place,
      ),
    );
  }
  return entries;
}

/// [count] closes drifting up to [end].
List<int> _walk(int end, int count, int seed) {
  final random = Random(seed);
  final values = List.filled(count, end);
  for (var i = count - 2; i >= 0; i--) {
    final step = (random.nextDouble() - 0.44) * 0.018;
    values[i] = (values[i + 1] * (1 - step)).round();
  }
  return values;
}
