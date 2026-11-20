part of 'seed.dart';

/// Writes the plainer months before April 2026: salary, rent, groceries,
/// coffee, fuel and a few one-off events, with the card paid off, cash
/// drawn as spent and savings swept away each month, so that only the
/// bank keeps a remainder. Returns that remainder, for the bank's opening.
// Exception to function length: two years of made-up entries, one a
// line; data, not steps to follow.
int _history(_Add add) {
  var bankNet = 0;
  for (var i = 0; i < _historyMonths; i++) {
    final first = DateTime.utc(2025, 1 + i);
    final year = first.year;
    final m = first.month;
    // A small, repeatable wobble from month to month.
    int wobble(int k) => (i * 37 + k * 53) % 17;
    var card = 0;
    var cash = 0;
    var bank = 0;
    void spend(
      int day,
      int amount,
      String account,
      String category,
      String note, {
      String merchant = '',
      List<String> tags = const [],
    }) {
      add(
        m,
        day,
        EntryType.expense,
        amount,
        account,
        category,
        note,
        year: year,
        merchant: merchant,
        tags: tags,
      );
      switch (account) {
        case 'card':
          card += amount;
        case 'cash':
          cash += amount;
        default:
          bank += amount;
      }
    }

    final salary = year == 2025 ? 50000 : 52000;
    add(m, 1, EntryType.income, salary, 'bank', '薪資收入', '每月薪資', year: year);
    spend(1, year == 2025 ? 12000 : 12500, 'bank', '居家生活', '$m月房租');
    for (final day in const [5, 13, 21]) {
      spend(
        day,
        1100 + wobble(day) * 40,
        'card',
        '飲食日常',
        '週末採買',
        merchant: '全聯福利中心',
        tags: const ['家用'],
      );
    }
    for (final day in const [8, 22]) {
      spend(day, 150 + wobble(day) * 5, 'cash', '飲食日常', '咖啡', merchant: '星巴克');
    }
    spend(16, 2400 + wobble(3) * 60, 'cash', '飲食日常', '外食', merchant: '八方雲集');
    spend(
      11,
      1500 + wobble(4) * 90,
      'card',
      '購物休閒',
      '生活用品',
      merchant: '家樂福',
      tags: const ['家用'],
    );
    spend(19, 850 + wobble(5) * 20, 'card', '交通通勤', '加油', merchant: '台灣中油');
    spend(18, 699, 'bank', '居家生活', '網路費');
    spend(21, 570, 'card', '訂閱服務', '影音與音樂訂閱');
    spend(
      20,
      1600 + wobble(6) * 30,
      'bank',
      '居家生活',
      '水電瓦斯',
      tags: const ['家用'],
    );
    spend(25, 2800, 'bank', '其他支出', '保險費');
    spend(14, 2200 + wobble(7) * 80, 'card', '購物休閒', '網購', merchant: 'momo購物網');
    for (final day in const [3, 10, 17, 24]) {
      spend(
        day,
        380 + wobble(day) * 15,
        'cash',
        '飲食日常',
        '午餐',
        merchant: '八方雲集',
      );
    }
    spend(6, 1000, 'cash', '交通通勤', '悠遊卡加值');
    if (year == 2025 && m == 8) {
      spend(9, 18600, 'card', '購物休閒', '日本旅遊・購物', tags: const ['日本旅遊']);
      spend(2, 12800, 'card', '交通通勤', '日本來回機票', tags: const ['日本旅遊']);
    }
    if (m == 12) {
      spend(20, 3200, 'card', '其他支出', '聖誕禮物', tags: const ['禮物']);
    }
    if (year == 2026 && m == 2) {
      spend(15, 8000, 'cash', '其他支出', '春節紅包', tags: const ['禮物']);
    }
    // Pay the card and draw the cash, then sweep to savings.
    add(
      m,
      28,
      EntryType.transfer,
      card,
      'bank',
      '轉帳',
      '信用卡繳款',
      year: year,
      to: 'card',
    );
    add(
      m,
      2,
      EntryType.transfer,
      cash,
      'bank',
      '轉帳',
      '提款',
      year: year,
      to: 'cash',
    );
    add(
      m,
      2,
      EntryType.transfer,
      _toSavings,
      'bank',
      '轉帳',
      '存到儲蓄',
      year: year,
      to: 'savings',
    );
    add(
      m,
      2,
      EntryType.transfer,
      _toDigital,
      'bank',
      '轉帳',
      '存到數位帳戶',
      year: year,
      to: 'digital',
    );
    bankNet += salary - bank - card - cash - _toSavings - _toDigital;
  }
  return bankNet;
}
