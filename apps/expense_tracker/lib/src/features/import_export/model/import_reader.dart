part of 'import_export.dart';

final class _Reader {
  _Reader(this.ledger, this.fallback)
    : _names = {for (final a in ledger.accounts.all) a.name: a.id};

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
    _problems.add('第 $line 行：$why');
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
    for (final c in [...ledger.categories.all, ..._categories]) {
      if (c.name == name) return c.income == income ? name : other;
    }
    // A name the ledger keeps for itself is not made a category.
    if (!ledger.categories.isNameFree(name)) return other;
    final count = ledger.categories.all.length + _categories.length;
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
    if (!income && _isSplit(written)) {
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
        for (final t in _tagsIn(cell('標籤')))
          if (t.isNotEmpty) t,
      ],
      installments: card && !income ? int.tryParse(cell('分期')) ?? 0 : 0,
      home: from.foreign
          ? home ?? ledger.marketData.toHome(amount, from.currency)
          : null,
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
      for (final e in [...ledger.entries.all, for (final (_, f) in _found) f])
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
    final inBook = ledger.entries.byId(e.id) == null
        ? e.amount
        : ledger.refundable(e);
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
      average: kind == _Kind.sell && cell('成本算法').contains('平均'),
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
        // Only a sale or a reduction can leave a stock short of shares.
        final takes = e.type == EntryType.sell || e.isReduction;
        if (takes && !ledger.holdsWith([...trades, e])) {
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

bool _already(Ledger ledger, Entry entry) => ledger.entries
    .inMonth(entry.date.year, entry.date.month)
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
  final known = ledger.categories.forEntries(income: false).map((c) => c.name);
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
  final found = text.contains('發票號碼')
      ? _invoiceCsv(ledger, text, account: account)
      : _invoiceLines(ledger, text, account: account);
  // Each is checked as one typed in would be: an invoice is in NT$, so a
  // foreign-currency account, for one, is refused rather than recorded at
  // the wrong value.
  if (ledger.account(account).currency != homeCode) {
    return Import(
      const [],
      found.skipped + found.entries.length,
      problems: const ['電子發票是新台幣，請選新台幣帳戶付款'],
    );
  }
  final kept = <Entry>[];
  final problems = [...found.problems];
  var skipped = found.skipped;
  for (final entry in found.entries) {
    final problem = ledger.problemWith(entry, holdings: false);
    if (problem == null) {
      kept.add(entry);
    } else {
      skipped++;
      problems.add('${entry.merchant}：$problem');
    }
  }
  return Import(kept, skipped, problems: problems);
}

/// The ministry's M and D lines.
Import _invoiceLines(Ledger ledger, String text, {required String account}) {
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
  final problems = <String>[];
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
            _hasInvoice(ledger, day, number, shop: shop, amount: value));
    final why = day == null
        ? '日期看不懂'
        : value == null || value <= 0
        ? '金額看不懂'
        : voided
        ? '已作廢'
        : seen
        ? '已經記過'
        : null;
    if (why != null) {
      skipped++;
      problems.add('${number.isEmpty ? shop : number}：$why');
      continue;
    }
    final bought = items[number] ?? const [];
    entries.add(_invoice(ledger, account, day!, shop, number, bought, value!));
  }
  return Import(entries, skipped, problems: problems);
}

/// The ministry's 消費明細 CSV, one row per item, added up per invoice by
/// `data_exchange`. A row it cannot read leaves the whole file out.
Import _invoiceCsv(Ledger ledger, String text, {required String account}) {
  final List<EInvoice> invoices;
  try {
    invoices = parseEInvoices(text);
  } on FormatException {
    // Said to the person as a problem of the file.
    return const Import([], 1, problems: ['檔案格式看不懂']);
  }
  final entries = <Entry>[];
  final problems = <String>[];
  var skipped = 0;
  for (final invoice in invoices) {
    final BusinessDate(:year, :month, :day) = invoice.date;
    final date = DateTime.utc(year, month, day);
    final number = invoice.number;
    final value = invoice.amount.minorUnits.toInt();
    if (value <= 0 ||
        entries.any((e) => e.note.contains(number)) ||
        _hasInvoice(
          ledger,
          date,
          number,
          shop: invoice.seller,
          amount: value,
        )) {
      skipped++;
      problems.add('$number：${value <= 0 ? '金額看不懂' : '已經記過'}');
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
  return Import(entries, skipped, problems: problems);
}

/// The open NT$ account [shop] was last paid from, if any.
String? _usualAccount(Ledger ledger, String shop) {
  final last = shop.isEmpty ? null : ledger.lastAt(shop);
  if (last == null) return null;
  final account = ledger.account(last.account);
  if (account.archived || account.currency != homeCode) return null;
  if (!ledger.accounts.contains(account.id)) return null;
  return account.id;
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
    // The account the shop was last paid from, while it is open and in
    // NT$; the one chosen for the import otherwise.
    account: _usualAccount(ledger, shop) ?? account,
    category: guessCategory(ledger, shop, bought.join(' ')),
    note: '$what$more 發票 $number'.trim(),
    merchant: shop,
    tags: const ['發票'],
  );
}

/// Whether the invoice [number] of [day] is in the book already, as an
/// import or a scan would find it.
bool invoiceRecorded(Ledger ledger, DateTime day, String number) =>
    _hasInvoice(ledger, day, number);

/// Whether the invoice [number] of [day] was imported before: its number
/// is in a note, or an invoice entry of that day, shop and [amount] is
/// there, as when its note was edited since.
bool _hasInvoice(
  Ledger ledger,
  DateTime? day,
  String number, {
  String shop = '',
  int? amount,
}) {
  if (day == null) return false;
  return ledger.entries
      .inMonth(day.year, day.month)
      .any(
        (e) =>
            e.note.contains(number) ||
            (e.tags.contains('發票') &&
                // An entry still noting its own number is another invoice.
                !e.note.contains(RegExp(r'發票 \S')) &&
                e.date == day &&
                e.merchant == shop &&
                e.amount == amount),
      );
}
