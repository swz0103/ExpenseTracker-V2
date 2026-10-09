import 'package:flutter/painting.dart' show Color;

import 'ledger.dart';

/// The preview's made-up book as of 2026-10-04, the same fixture as the
/// approved web preview (v114): six months of salary, rent and everyday
/// spending, a busy fourth of October, sixteen accounts and twelve
/// holdings.
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
    String? to,
    String? recurring,
  }) {
    entries.add(
      Entry(
        id: 'seed-${++serial}',
        date: DateTime.utc(2026, month, day),
        type: type,
        amount: amount,
        account: account,
        category: category,
        note: note,
        to: to,
        recurring: recurring,
      ),
    );
  }

  const spend = EntryType.expense;
  for (var m = 4; m <= 9; m++) {
    add(m, 1, EntryType.income, 52000, 'bank', '薪資收入', '每月薪資');
    add(m, 1, spend, 12500, 'bank', '居家生活', '$m月房租');
    add(m, 6, spend, 3800 + m * 170, 'bank', '飲食日常', '日常餐飲');
    add(m, 10, spend, 1800 + m * 95, 'card', '購物休閒', '生活用品');
    add(m, 14, spend, 1100, 'bank', '交通通勤', '交通儲值');
    add(m, 18, spend, 699, 'bank', '居家生活', '網路費');
    add(m, 21, spend, 570, 'bank', '訂閱服務', '影音與音樂訂閱');
    add(m, 26, spend, 2600 + m * 180, 'cash', '飲食日常', '外食與咖啡');
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
  add(10, 1, EntryType.income, 52000, 'bank', '薪資收入', '十月薪資');
  add(10, 1, spend, 12500, 'bank', '居家生活', '十月房租', recurring: 'rent');
  add(10, 2, spend, 1680, 'card', '飲食日常', '全聯・週末採買');
  add(10, 2, spend, 480, 'bank', '交通通勤', '悠遊卡加值');
  add(10, 3, spend, 179, 'card', '訂閱服務', 'Spotify Premium');
  add(10, 3, spend, 1290, 'card', '購物休閒', '無印良品・收納用品');
  add(10, 4, spend, 240, 'cash', '飲食日常', '日式定食・午餐');
  add(10, 4, spend, 150, 'cash', '飲食日常', '巷口咖啡');
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
    accounts: const [
      Account('bank', '日常銀行', AccountKind.bank, 45000),
      Account('cash', '隨身現金', AccountKind.cash, 36000),
      Account('digital', '數位帳戶', AccountKind.bank, 80000, icon: 'phone'),
      Account('card', '日常信用卡', AccountKind.card, -4680),
      Account('savings', '儲蓄帳戶', AccountKind.bank, 125000, icon: 'safe'),
      Account('travel', '旅遊基金', AccountKind.bank, 42000, icon: 'suitcase'),
      Account('salary', '薪轉帳戶', AccountKind.bank, 26500, icon: 'briefcase'),
      Account('line-pay', 'LINE Pay', AccountKind.wallet, 6800, icon: 'chat'),
      Account('jkopay', '街口支付', AccountKind.wallet, 4200, icon: 'store'),
      Account('pxpay', '全支付', AccountKind.wallet, 2800, icon: 'scan'),
      Account('easy-wallet', '悠遊付', AccountKind.wallet, 1200, icon: 'ticket'),
      Account('home-cash', '家用現金', AccountKind.cash, 8500, icon: 'coins'),
    ],
    categories: const [
      Category('居家生活', 'home', Color(0xFF78906D)),
      Category('飲食日常', 'food', Color(0xFFC28B60)),
      Category('交通通勤', 'travel', Color(0xFF6E929B)),
      Category('購物休閒', 'bag', Color(0xFF927EAA)),
      Category('訂閱服務', 'subscription', Color(0xFFB19A56)),
      Category('其他支出', 'other', Color(0xFFB77380)),
      Category('薪資收入', 'salary', Color(0xFF52745A), income: true),
      Category('股息收入', 'dividend', Color(0xFF76658A), income: true),
      Category('其他收入', 'income', Color(0xFF6E8A6A), income: true),
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
