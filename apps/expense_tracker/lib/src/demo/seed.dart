import 'package:flutter/painting.dart' show Color;

import 'ledger.dart';

/// The preview's made-up book as of 2026-10-04, the same fixture as the
/// approved web preview (v114): six months of salary, rent and everyday
/// spending, a busy fourth of October, sixteen accounts and twelve
/// holdings, with fifteen plainer months before them for the reports.
Ledger demoLedger() {
  final entries = <Entry>[];
  var serial = 0;
  void add(
    int month,
    int day,
    EntryType type,
    int amount,
    String account,
    String category,
    String note, {
    int year = 2026,
    String? to,
    String? recurring,
    String merchant = '',
    List<String> tags = const [],
    int installments = 0,
  }) {
    entries.add(
      Entry(
        id: 'seed-${++serial}',
        date: DateTime.utc(year, month, day),
        type: type,
        amount: amount,
        account: account,
        category: category,
        note: note,
        to: to,
        recurring: recurring,
        merchant: merchant,
        tags: tags,
        installments: installments,
      ),
    );
  }

  const spend = EntryType.expense;
  final bankBefore = _history(add);
  for (var m = 4; m <= 9; m++) {
    add(m, 1, EntryType.income, 52000, 'bank', '薪資收入', '每月薪資');
    add(m, 1, spend, 12500, 'bank', '居家生活', '$m月房租');
    add(
      m,
      6,
      spend,
      3800 + m * 170,
      'bank',
      '飲食日常',
      '日常餐飲',
      merchant: '全聯福利中心',
      tags: const ['家用'],
    );
    add(
      m,
      10,
      spend,
      1800 + m * 95,
      'card',
      '購物休閒',
      '生活用品',
      merchant: '家樂福',
      tags: const ['家用'],
    );
    add(m, 14, spend, 1100, 'bank', '交通通勤', '交通儲值');
    add(m, 18, spend, 699, 'bank', '居家生活', '網路費');
    add(m, 21, spend, 570, 'bank', '訂閱服務', '影音與音樂訂閱');
    add(m, 26, spend, 2600 + m * 180, 'cash', '飲食日常', '外食與咖啡', merchant: '星巴克');
    add(
      m,
      28,
      EntryType.transfer,
      1800 + m * 95,
      'bank',
      '轉帳',
      '信用卡繳款',
      to: 'card',
    );
  }
  // A phone in twelve card instalments, two of them paid off.
  add(
    7,
    12,
    spend,
    36000,
    'card',
    '購物休閒',
    'iPhone 17',
    merchant: 'Apple',
    installments: 12,
  );
  for (final m in const [8, 9]) {
    add(
      m,
      28,
      EntryType.transfer,
      3000,
      'bank',
      '轉帳',
      'iPhone 分期繳款',
      to: 'card',
    );
  }
  add(10, 1, EntryType.income, 52000, 'bank', '薪資收入', '十月薪資');
  add(10, 1, spend, 12500, 'bank', '居家生活', '十月房租', recurring: 'rent');
  add(
    10,
    2,
    spend,
    1680,
    'card',
    '飲食日常',
    '全聯・週末採買',
    merchant: '全聯福利中心',
    tags: const ['家用'],
  );
  add(10, 2, spend, 480, 'bank', '交通通勤', '悠遊卡加值');
  add(10, 3, spend, 179, 'card', '訂閱服務', 'Spotify Premium');
  add(
    10,
    3,
    spend,
    1290,
    'card',
    '購物休閒',
    '無印良品・收納用品',
    merchant: '無印良品',
    tags: const ['家用'],
  );
  add(10, 4, spend, 240, 'cash', '飲食日常', '日式定食・午餐');
  add(10, 4, spend, 150, 'cash', '飲食日常', '巷口咖啡', merchant: '星巴克');
  for (final (amount, note) in const [
    (65, '日式餐點'),
    (45, '飲品採買'),
    (90, '下午點心'),
    (120, '超市採買'),
    (180, '日常點心'),
    (160, '餐點・外食'),
    (140, '咖啡・休閒'),
    (200, '週末點心'),
  ]) {
    add(10, 4, spend, amount, 'cash', '飲食日常', note);
  }

  return Ledger(
    today: DateTime.utc(2026, 10, 4),
    accounts: [
      Account('bank', '日常銀行', AccountKind.bank, 45000 - bankBefore),
      const Account('cash', '隨身現金', AccountKind.cash, 36000),
      const Account(
        'digital',
        '數位帳戶',
        AccountKind.bank,
        80000 - _toDigital * _historyMonths,
        icon: 'phone',
      ),
      const Account(
        'card',
        '日常信用卡',
        AccountKind.card,
        -4680,
        closingDay: 1,
        dueDay: 15,
        limit: 100000,
      ),
      const Account(
        'savings',
        '儲蓄帳戶',
        AccountKind.bank,
        125000 - _toSavings * _historyMonths,
        icon: 'safe',
      ),
      const Account(
        'travel',
        '旅遊基金',
        AccountKind.bank,
        42000,
        icon: 'suitcase',
      ),
      const Account(
        'salary',
        '薪轉帳戶',
        AccountKind.bank,
        26500,
        icon: 'briefcase',
      ),
      const Account(
        'line-pay',
        'LINE Pay',
        AccountKind.wallet,
        6800,
        icon: 'chat',
      ),
      const Account('jkopay', '街口支付', AccountKind.wallet, 4200, icon: 'store'),
      const Account('pxpay', '全支付', AccountKind.wallet, 2800, icon: 'scan'),
      const Account(
        'easy-wallet',
        '悠遊付',
        AccountKind.wallet,
        1200,
        icon: 'ticket',
      ),
      const Account('home-cash', '家用現金', AccountKind.cash, 8500, icon: 'coins'),
    ],
    categories: const [
      Category('居家生活', 'home', Color(0xFF5C9A83)),
      Category('飲食日常', 'food', Color(0xFFD08B5B)),
      Category('交通通勤', 'travel', Color(0xFF5B8DB0)),
      Category('購物休閒', 'bag', Color(0xFF8E7CC0)),
      Category('訂閱服務', 'subscription', Color(0xFFC9A34A)),
      Category('其他支出', 'other', Color(0xFFB07A8C)),
      Category('薪資收入', 'salary', Color(0xFF2F7A65), income: true),
      Category('股息收入', 'dividend', Color(0xFF5A6FA8), income: true),
      Category('其他收入', 'income', Color(0xFF4E8A9A), income: true),
    ],
    entries: entries,
    holdings: const [
      Holding(
        '0050',
        '元大台灣50',
        shares: 3000,
        price: 58.2,
        cost: 154000,
        change: 900,
        dividends: 8100,
      ),
      Holding(
        '00878',
        '國泰永續高股息',
        shares: 5000,
        price: 22.3,
        cost: 103000,
        change: 250,
        dividends: 9450,
      ),
      Holding(
        '2330',
        '台積電',
        shares: 100,
        price: 1050,
        cost: 89500,
        change: 800,
        dividends: 2000,
      ),
      Holding(
        '0056',
        '元大高股息',
        shares: 1800,
        price: 36.5,
        cost: 60200,
        change: 180,
        dividends: 3800,
      ),
      Holding(
        '006208',
        '富邦台50',
        shares: 550,
        price: 112,
        cost: 53500,
        change: 330,
        dividends: 1650,
      ),
      Holding(
        '00919',
        '群益台灣精選高息',
        shares: 2400,
        price: 23.6,
        cost: 52800,
        change: 120,
        dividends: 3100,
      ),
      Holding(
        '2884',
        '玉山金',
        shares: 1300,
        price: 30.8,
        cost: 34600,
        change: -130,
        dividends: 1800,
      ),
      Holding(
        '2308',
        '台達電',
        shares: 70,
        price: 425,
        cost: 25600,
        change: 280,
        dividends: 700,
      ),
      Holding(
        '2412',
        '中華電',
        shares: 160,
        price: 128,
        cost: 18800,
        change: -80,
        dividends: 960,
      ),
      Holding(
        '2891',
        '中信金',
        shares: 350,
        price: 40.2,
        cost: 11900,
        change: 70,
        dividends: 500,
      ),
      Holding(
        '00929',
        '復華台灣科技優息',
        shares: 80,
        price: 19.8,
        cost: 1440,
        change: -8,
        dividends: 60,
      ),
      Holding('2603', '長榮', shares: 3, price: 188, cost: 510, change: 5),
    ],
    budgets: const [
      Budget(Ledger.allSpending, 32000),
      Budget('飲食日常', 8000),
      Budget('居家生活', 14000),
      Budget('交通通勤', 2500),
      Budget('購物休閒', 5000),
    ],
    recurring: const [
      Recurring(
        id: 'rent',
        name: '每月房租',
        amount: 12500,
        day: 1,
        account: 'bank',
        category: '居家生活',
      ),
      Recurring(
        id: 'netflix',
        name: 'Netflix',
        amount: 390,
        day: 5,
        account: 'card',
        category: '訂閱服務',
      ),
      Recurring(
        id: 'internet',
        name: '家用網路',
        amount: 699,
        day: 10,
        account: 'bank',
        category: '居家生活',
      ),
      Recurring(
        id: 'yoga',
        name: '瑜珈月費',
        amount: 1600,
        day: 15,
        account: 'bank',
        category: '購物休閒',
      ),
    ],
  );
}

/// How many months [_history] writes: January 2025 to March 2026.
const _historyMonths = 15;

/// What each of those months moves to savings and the digital account.
const _toSavings = 8000;
const _toDigital = 5000;

typedef _Add = void Function(
  int month,
  int day,
  EntryType type,
  int amount,
  String account,
  String category,
  String note, {
  int year,
  String? to,
  String? recurring,
  String merchant,
  List<String> tags,
});

/// Writes the plainer months before April 2026: salary, rent, groceries,
/// coffee, fuel and a few one-off events, with the card paid off, cash
/// drawn as spent and savings swept away each month, so that only the
/// bank keeps a remainder. Returns that remainder, for the bank's opening.
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
