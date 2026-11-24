// Exception to shared words: the CSV columns read, as written by
// import_export.dart and by other apps; a file format, not screen words.
part of 'import_export.dart';

final class _Reader {
  _Reader(this.book, this.fallback)
    : _names = {for (final a in book.accounts.all) plainText(a.name): a.id},
      _categoryByName = {
        for (final c in book.categories.all.reversed) plainText(c.name): c,
      };

  final ImportBook book;
  final String fallback;
  final Map<String, String> _names;
  final _accounts = <Account>[];
  final _categories = <Category>[];

  /// Every category of the book and of this file, by name, the book's
  /// first where two share one: found at once, not looked for line by
  /// line through them all.
  final Map<String, Category> _categoryByName;

  /// The lines read, with the line each came from.
  final _found = <(int, Entry)>[];

  /// Refunds already given against spending in this file, by its id.
  final _refunded = <String, int>{};
  final _problems = <String>[];

  /// The line of the file being read.
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
    return book.account(id);
  }

  /// The account named [name], added when the book has none.
  String _accountNamed(String name) {
    if (name.isEmpty) return fallback;
    final known = _names[name];
    if (known != null) return known;
    final kind = _kindOf(name);
    final card = kind == AccountKind.card;
    final made = Account(
      book.newId(),
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
    if (_categoryByName[name] case final c?) {
      return c.income == income ? c.name : other;
    }
    // A name the book keeps for itself is not made a category.
    if (!book.categories.isNameFree(name)) return other;
    final count = book.categories.all.length + _categories.length;
    final made = Category(
      name,
      income ? 'income' : 'other',
      _shades[count % _shades.length],
      income: income,
    );
    _categories.add(made);
    _categoryByName[name] = made;
    return name;
  }

  /// Reads the [line] of the file; why it cannot be kept, or null when
  /// it was.
  String? read(String Function(String) cell, {required int line}) {
    _line = line;
    final read = readImportDay(
      cell('日期'),
      latest: BusinessDate.of(latestEntryDay(book.today)),
    );
    if (read case DayRefused(:final problem)) return dayProblemWords(problem);
    final day = _utcDay(read)!;
    final typed = cell('類型');
    final named = _kinds[typed] ?? _kinds[typed.toLowerCase()];
    if (typed.isNotEmpty && named == null) return '不認得的類型「$typed」';
    final account = _accountNamed(cell('帳戶'));
    final from = _account(account);
    final (value, unreadable) = _cellAmount(cell, '金額', from.currency);
    if (unreadable != null) return unreadable;
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
      _Kind.refund => _refund(cell, day, account, from, amount, note),
      _Kind.transfer => _transfer(cell, day, account, from, amount, note),
      _ => _investment(cell, kind, day, account, from, amount, note),
    };
    if (entry is! Entry) return entry as String;
    final made = entry;
    // Checked as one typed in would be, with the accounts this file adds;
    // the shares its trades take are checked together when it is added.
    final failure = book.entryValidator.validate(
      made,
      holdings: false,
      opening: _accounts,
    );
    if (failure is MissingHomeAmount) return importMissingHomeWords;
    if (failure != null) return validationMessage(failure);
    if (_already(book, made)) return '帳本裡已經有這一筆';
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
        final part = _amount(
          piece.substring(at + 1),
          from.currency,
        ).minorOrNull;
        if (part == null || part <= 0) return '拆分的金額看不懂';
        final name = piece.substring(0, at).trim();
        parts.add((_categoryNamed(name, income: false), part));
      }
      // One part is none; parts that do not add up to the amount are the
      // ledger's to refuse, as a split typed in.
      if (parts.length == 1) parts = [];
    }
    // Exception to glossary: the file format's column, kept so files written before read back.
    final (home, homeProblem) = _cellAmount(cell, '台幣金額');
    if (homeProblem != null) return homeProblem;
    final card = from.kind == AccountKind.card;
    return Entry(
      id: book.newId(),
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
          ? home ?? book.marketData.toHome(amount, from.currency)
          : null,
    );
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
    final (charged, feeProblem) = _cellAmount(cell, '手續費');
    final (received, receivedProblem) = target.currency == from.currency
        ? (null, null)
        : _cellAmount(cell, '轉入金額', target.currency);
    if (feeProblem ?? receivedProblem case final why?) return why;
    final fee = charged ?? 0;
    if (target.kind == AccountKind.card && fee > 0) return '繳卡費不能有手續費';
    if (fee > 0 && from.foreign) return '外幣帳戶轉出不能記手續費';
    return Entry(
      id: book.newId(),
      date: day,
      type: EntryType.transfer,
      amount: amount,
      account: account,
      category: transferCategory,
      note: note,
      to: to,
      fee: fee,
      received: received,
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
    final (fee, feeProblem) = trade ? _cellAmount(cell, '手續費') : (null, null);
    final (tax, taxProblem) = kind == _Kind.cut
        ? (null, null)
        : _cellAmount(cell, '稅');
    if (feeProblem ?? taxProblem case final why?) return why;
    return Entry(
      id: book.newId(),
      date: day,
      type: switch (kind) {
        _Kind.buy => EntryType.buy,
        _Kind.sell => EntryType.sell,
        _ => EntryType.dividend,
      },
      amount: amount,
      account: account,
      category: trade ? investmentCategory : dividendCategory,
      note: note,
      holding: code,
      shares: switch (kind) {
        _Kind.cash => 0,
        _Kind.cut => -shares,
        _ => shares,
      },
      fee: fee ?? 0,
      tax: tax ?? 0,
      split: kind == _Kind.split,
      average: kind == _Kind.sell && cell('成本算法').contains('平均'),
    );
  }

  /// What was read, oldest first, less trades that sell or take away more
  /// shares than are held by then: null after each step of the work, so
  /// a long file can be read a slice at a time, then the import, last.
  Iterable<Import?> result() sync* {
    // By day, then in the order read: each day's places gathered a step
    // at a time, then only the days sorted.
    final byDay = <int, List<int>>{};
    for (final (i, (_, e)) in _found.indexed) {
      (byDay[e.date.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay] ??=
              [])
          .add(i);
      yield null;
    }
    final days = byDay.keys.toList()..sort();
    yield null;
    final kept = <Entry>[];
    final trades = <Entry>[];
    final used = <String>{};
    final cats = <String>{};
    for (final i in days.expand((day) => byDay[day]!)) {
      final (line, e) = _found[i];
      yield null;
      if (e.isInvestment) {
        // Only a sale or a reduction can leave a stock short of shares.
        final takes = e.type == EntryType.sell || e.isReduction;
        if (takes && !book.entryValidator.holdsWith([...trades, e])) {
          skip(line, '${e.holding} 賣出或減少的股數超過當時持股');
          continue;
        }
        trades.add(e);
      }
      kept.add(e);
      used.add(e.account);
      if (e.to case final to?) used.add(to);
      cats.add(e.category);
      for (final (name, _) in e.parts) {
        cats.add(name);
      }
    }
    yield Import(
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

// Exception to as-of-today: a duplicate check looks at every entry written.
bool _already(ImportBook book, Entry entry) => book.entries
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

/// Spending from the Ministry of Finance e-invoice export: an M line per
/// invoice (載具名稱|載具號碼|日期|統編|店名|發票號碼|總金額|狀態) and D
/// lines with its items. Each invoice becomes spending on [account] at
/// the shop, noted with its invoice number; void ones and invoices
/// already in the book are left out. The ministry's 消費明細 CSV, with a
/// 發票號碼 column, is read too.
Import importInvoices(ImportBook book, String text, {required String account}) {
  final found = text.contains('發票號碼')
      ? _invoiceCsv(book, text, account: account)
      : _invoiceLines(book, text, account: account);
  // Each is checked as one typed in would be: an invoice is in NT$, so a
  // foreign-currency account, for one, is refused rather than recorded at
  // the wrong value.
  if (book.account(account).currency != homeCode) {
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
    final failure = book.entryValidator.validate(entry, holdings: false);
    final problem = failure == null ? null : validationMessage(failure);
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
Import _invoiceLines(ImportBook book, String text, {required String account}) {
  final items = <String, List<String>>{};
  final heads = <List<String>>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    final cells = line.split('|').map((c) => plainText(c).trim()).toList();
    if (cells.first == 'M' && cells.length >= 8) heads.add(cells);
    if (cells.first == 'D' && cells.length >= 4) {
      (items[cells[1]] ??= []).add(cells[3]);
    }
  }
  final entries = <Entry>[];
  final problems = <String>[];
  final numbers = <String>{};
  var skipped = 0;
  for (final cells in heads) {
    final read = readImportDay(
      cells[3],
      latest: BusinessDate.of(latestEntryDay(book.today)),
    );
    final day = _utcDay(read);
    final shop = cells[5];
    final number = cells[6];
    final value = _amount(cells[7]).minorOrNull;
    final voided = cells.length > 8 && cells[8].contains('作廢');
    final seen =
        number.isNotEmpty &&
        (numbers.contains(number) ||
            hasInvoice(book.entries, day, number, shop: shop, amount: value));
    final why = read is DayRefused
        ? dayProblemWords(read.problem)
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
    numbers.add(number);
    entries.add(_invoice(book, account, day!, shop, number, bought, value!));
  }
  return Import(entries, skipped, problems: problems);
}

/// The ministry's 消費明細 CSV, one row per item, added up per invoice by
/// `data_exchange`. A row it cannot read leaves the whole file out; an
/// invoice whose rows disagree, or dated too early, is left out, named.
Import _invoiceCsv(ImportBook book, String text, {required String account}) {
  final EInvoiceFile file;
  try {
    file = readEInvoices(text);
  } on FormatException {
    // Said to the person as a problem of the file.
    return const Import([], 1, problems: ['檔案格式看不懂']);
  }
  final entries = <Entry>[];
  final problems = [
    for (final (:number, line: _, :why) in file.refused)
      '$number：${invoiceRefusalWords(why)}',
  ];
  var skipped = file.refused.length;
  for (final invoice in file.invoices) {
    final BusinessDate(:year, :month, :day) = invoice.date;
    final date = DateTime.utc(year, month, day);
    final number = invoice.number;
    final value = invoice.amount.minorUnits.toInt();
    // The file holds each number once (readEInvoices).
    if (value <= 0 ||
        hasInvoice(
          book.entries,
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
        book,
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
String? _usualAccount(ImportBook book, String shop) {
  final last = shop.isEmpty ? null : book.entryQueryService.lastAt(shop);
  if (last == null) return null;
  final account = book.account(last.account);
  if (account.archived || account.currency != homeCode) return null;
  if (!book.accounts.contains(account.id)) return null;
  return account.id;
}

/// Spending at [shop] on [day] for the invoice [number], noted with its
/// first item and how many there were.
Entry _invoice(
  ImportBook book,
  String account,
  DateTime day,
  String shop,
  String number,
  List<String> bought,
  int value,
) {
  return Entry(
    id: book.newId(),
    date: day,
    type: EntryType.expense,
    amount: value,
    // The account the shop was last paid from, while it is open and in
    // NT$; the one chosen for the import otherwise.
    account: _usualAccount(book, shop) ?? account,
    category: guessCategory(
      book.entryQueryService,
      book.categories,
      shop,
      bought.join(' '),
    ),
    note: invoiceNote(bought, number),
    merchant: shop,
    tags: const [Words.invoice],
    mark: EntryMark.invoice,
  );
}
