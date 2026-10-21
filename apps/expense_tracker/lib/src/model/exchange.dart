import 'package:core/foundation_values.dart' show BusinessDate, Currency;
import 'package:domain/data_exchange.dart';
import 'package:flutter/painting.dart' show Color;

import 'amounts.dart';
import 'checks.dart';
import 'ledger.dart';

/// What an import found: the entries to add, the accounts and categories
/// they name that the book does not have yet, and the lines left out, as
/// already in the book or unusable.
final class Import {
  const Import(
    this.entries,
    this.skipped, {
    this.accounts = const [],
    this.categories = const [],
    this.problems = const [],
  });

  final List<Entry> entries;
  final int skipped;
  final List<Account> accounts;
  final List<Category> categories;

  /// Why lines were left out, such as 「第 3 行：日期看不懂」; the first
  /// few only.
  final List<String> problems;
}

/// Adds what [found] holds to [ledger]: its new accounts and categories
/// first, then its entries.
void addImport(Ledger ledger, Import found) {
  found.accounts.forEach(ledger.addAccount);
  found.categories.forEach(ledger.addCategory);
  ledger.addAll(found.entries);
}

const _header = [
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
];

/// The name an entry's kind has in a CSV.
String _typeOf(Entry e) => switch (e) {
  Entry(isRefund: true) => '退款',
  Entry(type: EntryType.expense) => '支出',
  Entry(type: EntryType.income) => '收入',
  Entry(type: EntryType.transfer) => '轉帳',
  Entry(type: EntryType.buy) => '買進',
  Entry(type: EntryType.sell) => '賣出',
  Entry(type: EntryType.dividend, split: true) => '分割',
  Entry(type: EntryType.dividend, shares: < 0) => '減資',
  Entry(type: EntryType.dividend, shares: > 0) => '配股',
  Entry(type: EntryType.dividend) => '股息',
};

/// [entries], oldest first, as CSV with a header line that Excel opens
/// as UTF-8. Every kind of entry is written with what it takes to read
/// it back: amounts in their account's currency, a split as
/// 分類=金額;分類=金額, fees and taxes in NT$.
String toCsv(Ledger ledger, List<Entry> entries) {
  final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
  return writeCsv([_header, for (final e in sorted) _row(ledger, e)]);
}

List<String> _row(Ledger ledger, Entry e) {
  String count(int n) => n == 0 ? '' : '$n';
  final account = ledger.account(e.account);
  final to = e.to == null ? null : ledger.account(e.to!);
  final received = e.received;
  return [
    _day(e.date),
    _typeOf(e),
    plainIn(e.amount, account.currency),
    account.name,
    to?.name ?? '',
    if (e.parts.isEmpty)
      e.category
    else
      [
        for (final (name, part) in e.parts)
          '$name=${plainIn(part, account.currency)}',
      ].join(';'),
    e.merchant,
    e.tags.join(' '),
    e.note,
    e.holding ?? '',
    count(e.shares.abs()),
    count(e.fee),
    count(e.tax),
    count(e.installments),
    if (received == null || to == null) '' else plainIn(received, to.currency),
    e.home == null ? '' : '${e.home}',
  ];
}

String _day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _two(int n) => n.toString().padLeft(2, '0');

/// The rows of [text] read as CSV, a leading byte order mark and blank
/// lines left out. A quote left open runs to the end, as a spreadsheet
/// reads it.
List<List<String>> parseCsv(String text) {
  try {
    return readCsv(text);
  } on FormatException {
    return readCsv('$text"');
  }
}

/// A day written as 2026-03-05, 2026/3/5, 20260305 or, in the Republic
/// of China calendar, 1150305; null when unreadable.
DateTime? readDay(String text) {
  final value = text.trim();
  final digits = RegExp(r'^\d{7,8}$');
  if (digits.hasMatch(value)) {
    final cut = value.length - 4;
    var year = int.parse(value.substring(0, cut));
    if (value.length == 7) year += 1911;
    final month = int.parse(value.substring(cut, cut + 2));
    final day = int.parse(value.substring(cut + 2));
    return _valid(year, month, day);
  }
  final parts = value.split(RegExp(r'[-/.]'));
  if (parts.length != 3) return null;
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.contains(null)) return null;
  var year = numbers[0]!;
  if (year < 1000) year += 1911;
  return _valid(year, numbers[1]!, numbers[2]!);
}

DateTime? _valid(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime.utc(year, month, day);
  return date.month == month ? date : null;
}

/// [text] in the smallest unit of [currency]: `1,200` and `NT$ 120` read
/// as written, more decimals than the currency has are rounded.
int? _amount(String text, [String currency = homeCode]) {
  final value = text.replaceAll(RegExp(r'[,\s$]|NT'), '');
  final exact = minorOf(value, currency);
  if (exact != null) return exact;
  final rounded = double.tryParse(value);
  if (rounded == null) return null;
  return (rounded * (Currency.scaleOf(currency) == 0 ? 1 : 100)).round();
}

/// The kinds a CSV line can be, by the names it may use.
enum _Kind {
  expense,
  income,
  transfer,
  buy,
  sell,
  cash,
  stock,
  split,
  cut,
  refund,
}

const _kinds = {
  '支出': _Kind.expense,
  'expense': _Kind.expense,
  '收入': _Kind.income,
  'income': _Kind.income,
  '轉帳': _Kind.transfer,
  'transfer': _Kind.transfer,
  '買進': _Kind.buy,
  '買入': _Kind.buy,
  'buy': _Kind.buy,
  '賣出': _Kind.sell,
  'sell': _Kind.sell,
  '股息': _Kind.cash,
  '現金股利': _Kind.cash,
  'dividend': _Kind.cash,
  '配股': _Kind.stock,
  '股票股利': _Kind.stock,
  '分割': _Kind.split,
  '減資': _Kind.cut,
  '退款': _Kind.refund,
  'refund': _Kind.refund,
};

/// Colours for categories an import adds.
const _shades = [
  Color(0xFF5C9A83),
  Color(0xFFD08B5B),
  Color(0xFF5B8DB0),
  Color(0xFF8E7CC0),
  Color(0xFFC9A34A),
  Color(0xFFB07A8C),
  Color(0xFF4E8A9A),
];

/// Every kind of entry in [text], CSV with a header naming at least 日期
/// and 金額; the other columns of [toCsv] are read when there. Without a
/// type a negative amount is spending. An account or category the book
/// does not have is added, its kind told by its name (信用卡, 現金,
/// 錢包…); a line without an account goes to [fallback]. A line matching
/// an entry already in the book is left out, and so is one the book
/// would refuse, such as a sale of more shares than are held then.
Import importCsv(Ledger ledger, String text, {required String fallback}) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return const Import([], 0);
  final head = [for (final h in rows.first) h.trim()];
  if (!head.contains('日期') || !head.contains('金額')) {
    return Import(const [], rows.length, problems: const ['第一行要有「日期」和「金額」欄位']);
  }
  final reader = _Reader(ledger, fallback);
  for (final (i, row) in rows.skip(1).indexed) {
    String cell(String name) {
      final at = head.indexOf(name);
      return at < 0 || at >= row.length ? '' : row[at].trim();
    }

    final problem = reader.read(cell);
    if (problem != null) reader.skip(i + 2, problem);
  }
  return reader.result();
}

final class _Reader {
  _Reader(this.ledger, this.fallback)
    : _names = {for (final a in ledger.accounts) a.name: a.id};

  final Ledger ledger;
  final String fallback;
  final Map<String, String> _names;
  final _accounts = <Account>[];
  final _categories = <Category>[];

  /// The lines read, with the line each came from.
  final _found = <(int, Entry)>[];

  /// Refunds already given against spending in this file, by its id.
  final _refunded = <String, int>{};
  final _problems = <String>[];
  var _line = 1;
  var _skipped = 0;

  void skip(int line, String why) {
    _skipped++;
    if (_problems.length < 5) _problems.add('第 $line 行：$why');
  }

  Account _account(String id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return ledger.account(id);
  }

  /// The account named [name], added when the book has none.
  String _accountNamed(String name) {
    if (name.isEmpty) return fallback;
    final known = _names[name];
    if (known != null) return known;
    final kind = _kindOf(name);
    final card = kind == AccountKind.card;
    final made = Account(
      ledger.newId(),
      name,
      kind,
      0,
      closingDay: card ? 1 : null,
      dueDay: card ? 15 : null,
    );
    _accounts.add(made);
    return _names[name] = made.id;
  }

  static AccountKind _kindOf(String name) {
    bool has(List<String> words) => words.any(name.contains);
    if (has(['現金', '零錢'])) return AccountKind.cash;
    if (has(['悠遊', '一卡通', 'Pay', 'pay', '錢包', '支付'])) {
      return AccountKind.wallet;
    }
    if (has(['信用卡']) || name.endsWith('卡')) return AccountKind.card;
    if (has(['貸款', '房貸', '車貸', '信貸'])) return AccountKind.loan;
    if (has(['代墊', '應收', '借出'])) return AccountKind.receivable;
    return AccountKind.bank;
  }

  /// The category named [name] for income or spending, added when the
  /// book has none; a name the other side uses goes to 其他.
  String _categoryNamed(String name, {required bool income}) {
    final other = income ? '其他收入' : feeCategory;
    if (name.isEmpty) return other;
    for (final c in [...ledger.categories, ..._categories]) {
      if (c.name == name) return c.income == income ? name : other;
    }
    final count = ledger.categories.length + _categories.length;
    _categories.add(
      Category(
        name,
        income ? 'income' : 'other',
        _shades[count % _shades.length],
        income: income,
      ),
    );
    return name;
  }

  /// Reads one line; why it cannot be kept, or null when it was.
  String? read(String Function(String) cell) {
    _line++;
    final day = readDay(cell('日期'));
    if (day == null) return '日期看不懂';
    final typed = cell('類型');
    final named = _kinds[typed] ?? _kinds[typed.toLowerCase()];
    if (typed.isNotEmpty && named == null) return '不認得的類型「$typed」';
    final account = _accountNamed(cell('帳戶'));
    final from = _account(account);
    final value = _amount(cell('金額'), from.currency);
    final kind =
        named ??
        (value == null || value == 0
            ? null
            : value < 0
            ? _Kind.expense
            : _Kind.income);
    final stock = kind == _Kind.stock || kind == _Kind.split;
    if (kind == null || !stock && (value ?? 0) == 0) return '金額看不懂';
    final amount = (value ?? 0).abs();
    final note = cell('備註');
    final entry = switch (kind) {
      _Kind.expense || _Kind.income => _cashFlow(
        cell,
        day,
        account,
        from,
        amount,
        note,
        income: kind == _Kind.income,
      ),
      _Kind.refund => _refund(cell, day, account, amount, note),
      _Kind.transfer => _transfer(cell, day, account, from, amount, note),
      _ => _investment(cell, kind, day, account, from, amount, note),
    };
    if (entry is! Entry) return entry as String;
    final made = entry;
    if (!made.isReduction) {
      final problem = ledger.problemWith(made, holdings: false);
      if (problem != null) return problem;
    }
    if (_already(ledger, made)) return '帳本裡已經有這一筆';
    if (made.isRefund) {
      _refunded[made.refundOf!] = (_refunded[made.refundOf!] ?? 0) + amount;
    }
    _found.add((_line, made));
    return null;
  }

  Object _cashFlow(
    String Function(String) cell,
    DateTime day,
    String account,
    Account from,
    int amount,
    String note, {
    required bool income,
  }) {
    final written = cell('分類');
    var parts = <(String, int)>[];
    if (!income && written.contains('=')) {
      for (final piece in written.split(RegExp('[;；]'))) {
        final at = piece.lastIndexOf('=');
        if (at < 0) continue;
        final part = _amount(piece.substring(at + 1), from.currency);
        if (part == null || part <= 0) return '拆分的金額看不懂';
        final name = piece.substring(0, at).trim();
        parts.add((_categoryNamed(name, income: false), part));
      }
      final total = parts.fold(0, (sum, p) => sum + p.$2);
      if (total != amount) return '拆分的金額加起來不等於總額';
      if (parts.length == 1) parts = [];
    }
    final home = int.tryParse(cell('台幣金額').replaceAll(',', ''));
    final card = from.kind == AccountKind.card;
    return Entry(
      id: ledger.newId(),
      date: day,
      type: income ? EntryType.income : EntryType.expense,
      amount: amount,
      account: account,
      category: parts.isNotEmpty
          ? parts.first.$1
          : _categoryNamed(written, income: income),
      parts: parts,
      note: note,
      merchant: income ? '' : cell('商家'),
      tags: [
        for (final t in cell('標籤').split(RegExp(r'[\s;、]+')))
          if (t.isNotEmpty) t,
      ],
      installments: card && !income ? int.tryParse(cell('分期')) ?? 0 : 0,
      home: from.foreign ? home ?? ledger.toHome(amount, from.currency) : null,
    );
  }

  /// A refund of the latest spending on [account] up to [day] with that
  /// much left to give back, the same shop's first.
  Object _refund(
    String Function(String) cell,
    DateTime day,
    String account,
    int amount,
    String note,
  ) {
    final shop = cell('商家');
    final candidates = [
      for (final e in [...ledger.entries, for (final (_, f) in _found) f])
        if (e.type == EntryType.expense &&
            !e.isRefund &&
            e.account == account &&
            !e.date.isAfter(day) &&
            _left(e) >= amount)
          e,
    ]..sort((a, b) => b.date.compareTo(a.date));
    if (candidates.isEmpty) return '找不到可以退款的原支出';
    final original = candidates.firstWhere(
      (e) => shop.isNotEmpty && e.merchant == shop,
      orElse: () => candidates.first,
    );
    return Entry(
      id: ledger.newId(),
      date: day,
      type: EntryType.income,
      amount: amount,
      account: account,
      category: original.category,
      note: note,
      refundOf: original.id,
    );
  }

  int _left(Entry e) {
    final inBook = ledger.byId(e.id) == null ? e.amount : ledger.refundable(e);
    return inBook - (_refunded[e.id] ?? 0);
  }

  Object _transfer(
    String Function(String) cell,
    DateTime day,
    String account,
    Account from,
    int amount,
    String note,
  ) {
    final into = cell('轉入帳戶');
    if (into.isEmpty) return '轉帳要填轉入帳戶';
    final to = _accountNamed(into);
    final target = _account(to);
    if (from.kind == AccountKind.card) return '信用卡不能轉出，請記成支出';
    final fee = _amount(cell('手續費')) ?? 0;
    if (target.kind == AccountKind.card && fee > 0) return '繳卡費不能有手續費';
    if (fee > 0 && from.foreign) return '外幣帳戶轉出不能記手續費';
    return Entry(
      id: ledger.newId(),
      date: day,
      type: EntryType.transfer,
      amount: amount,
      account: account,
      category: transferCategory,
      note: note,
      to: to,
      fee: fee,
      received: target.currency == from.currency
          ? null
          : _amount(cell('轉入金額'), target.currency),
    );
  }

  Object _investment(
    String Function(String) cell,
    _Kind kind,
    DateTime day,
    String account,
    Account from,
    int amount,
    String note,
  ) {
    final code = cell('代號').toUpperCase();
    if (code.isEmpty) return '投資要填股票代號';
    if (from.kind == AccountKind.card) return '投資不能用信用卡';
    final shares = int.tryParse(cell('股數').replaceAll(',', '')) ?? 0;
    final needsShares = kind != _Kind.cash;
    if (needsShares && shares <= 0) return '請填股數';
    final trade = kind == _Kind.buy || kind == _Kind.sell;
    return Entry(
      id: ledger.newId(),
      date: day,
      type: switch (kind) {
        _Kind.buy => EntryType.buy,
        _Kind.sell => EntryType.sell,
        _ => EntryType.dividend,
      },
      amount: amount,
      account: account,
      category: trade ? '投資' : '股息收入',
      note: note,
      holding: code,
      shares: switch (kind) {
        _Kind.cash => 0,
        _Kind.cut => -shares,
        _ => shares,
      },
      fee: trade ? _amount(cell('手續費')) ?? 0 : 0,
      tax: kind == _Kind.cut ? 0 : _amount(cell('稅')) ?? 0,
      split: kind == _Kind.split,
    );
  }

  /// What was read, oldest first, less trades that sell or take away more
  /// shares than are held by then.
  Import result() {
    final sorted = [..._found]
      ..sort((a, b) {
        final byDay = a.$2.date.compareTo(b.$2.date);
        return byDay != 0 ? byDay : a.$1.compareTo(b.$1);
      });
    final kept = <Entry>[];
    final trades = <Entry>[];
    for (final (line, e) in sorted) {
      if (e.isInvestment) {
        if (!ledger.holdsWith([...trades, e])) {
          skip(line, '${e.holding} 賣出或減少的股數超過當時持股');
          continue;
        }
        trades.add(e);
      }
      kept.add(e);
    }
    final used = {
      for (final e in kept) ...[e.account, ?e.to],
    };
    final cats = {
      for (final e in kept) ...[e.category, for (final (c, _) in e.parts) c],
    };
    return Import(
      kept,
      _skipped,
      accounts: [
        for (final a in _accounts)
          if (used.contains(a.id)) a,
      ],
      categories: [
        for (final c in _categories)
          if (cats.contains(c.name)) c,
      ],
      problems: _problems,
    );
  }
}

bool _already(Ledger ledger, Entry entry) => ledger
    .entriesIn(entry.date.year, entry.date.month)
    .any(
      (e) =>
          e.date == entry.date &&
          e.type == entry.type &&
          e.amount == entry.amount &&
          e.account == entry.account &&
          e.note == entry.note &&
          e.to == entry.to &&
          e.holding == entry.holding &&
          e.shares == entry.shares,
    );

/// Words that tell a merchant's category when the book has not seen it.
const _hints = {
  '交通通勤': ['加油', '中油', '台塑', '停車', '捷運', '高鐵', '台鐵', '客運', 'Uber'],
  '飲食日常': ['7-ELEVEN', '統一超商', '全家', '萊爾富', '咖啡', '餐', '麵', '飯', '食品'],
  '居家生活': ['全聯', '家樂福', '大潤發', '屈臣氏', '康是美', '寶雅', 'IKEA'],
  '購物休閒': ['MOMO', 'PChome', '蝦皮', '誠品', '影城', '百貨'],
};

/// The category for spending at [merchant]: the one the book used last,
/// else one its name hints at, else 其他支出.
String guessCategory(Ledger ledger, String merchant, String items) {
  final used = ledger.categoryAt(merchant);
  if (used != null) return used;
  final known = ledger.categoriesFor(income: false).map((c) => c.name);
  final text = '$merchant $items'.toUpperCase();
  for (final MapEntry(key: category, value: words) in _hints.entries) {
    if (!known.contains(category)) continue;
    if (words.any((w) => text.contains(w.toUpperCase()))) return category;
  }
  return feeCategory;
}

/// Spending from the Ministry of Finance e-invoice export: an M line per
/// invoice (載具名稱|載具號碼|日期|統編|店名|發票號碼|總金額|狀態) and D
/// lines with its items. Each invoice becomes spending on [account] at
/// the shop, noted with its invoice number; void ones and invoices
/// already in the book are left out. The ministry's 消費明細 CSV, with a
/// 發票號碼 column, is read too.
Import importInvoices(Ledger ledger, String text, {required String account}) {
  if (text.contains('發票號碼')) {
    return _invoiceCsv(ledger, text, account: account);
  }
  final items = <String, List<String>>{};
  final heads = <List<String>>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    final cells = line.split('|').map((c) => c.trim()).toList();
    if (cells.first == 'M' && cells.length >= 8) heads.add(cells);
    if (cells.first == 'D' && cells.length >= 4) {
      (items[cells[1]] ??= []).add(cells[3]);
    }
  }
  final entries = <Entry>[];
  var skipped = 0;
  for (final cells in heads) {
    final day = readDay(cells[3]);
    final shop = cells[5];
    final number = cells[6];
    final value = _amount(cells[7]);
    final voided = cells.length > 8 && cells[8].contains('作廢');
    final seen =
        number.isNotEmpty &&
        (entries.any((e) => e.note.contains(number)) ||
            _hasInvoice(ledger, day, number));
    if (day == null || value == null || value <= 0 || voided || seen) {
      skipped++;
      continue;
    }
    final bought = items[number] ?? const [];
    entries.add(_invoice(ledger, account, day, shop, number, bought, value));
  }
  return Import(entries, skipped);
}

/// The ministry's 消費明細 CSV, one row per item, added up per invoice by
/// `data_exchange`. A row it cannot read leaves the whole file out.
Import _invoiceCsv(Ledger ledger, String text, {required String account}) {
  final List<EInvoice> invoices;
  try {
    invoices = parseEInvoices(text);
  } on FormatException {
    return const Import([], 1);
  }
  final entries = <Entry>[];
  var skipped = 0;
  for (final invoice in invoices) {
    final BusinessDate(:year, :month, :day) = invoice.date;
    final date = DateTime.utc(year, month, day);
    final number = invoice.number;
    final value = invoice.amount.minorUnits.toInt();
    if (value <= 0 ||
        entries.any((e) => e.note.contains(number)) ||
        _hasInvoice(ledger, date, number)) {
      skipped++;
      continue;
    }
    entries.add(
      _invoice(
        ledger,
        account,
        date,
        invoice.seller,
        number,
        invoice.items,
        value,
      ),
    );
  }
  return Import(entries, skipped);
}

/// Spending at [shop] on [day] for the invoice [number], noted with its
/// first item and how many there were.
Entry _invoice(
  Ledger ledger,
  String account,
  DateTime day,
  String shop,
  String number,
  List<String> bought,
  int value,
) {
  final what = bought.isEmpty ? '' : bought.first;
  final more = bought.length > 1 ? ' 等 ${bought.length} 項' : '';
  return Entry(
    id: ledger.newId(),
    date: day,
    type: EntryType.expense,
    amount: value,
    account: account,
    category: guessCategory(ledger, shop, bought.join(' ')),
    note: '$what$more 發票 $number'.trim(),
    merchant: shop,
    tags: const ['發票'],
  );
}

bool _hasInvoice(Ledger ledger, DateTime? day, String number) {
  if (day == null) return false;
  return ledger
      .entriesIn(day.year, day.month)
      .any((e) => e.note.contains(number));
}
