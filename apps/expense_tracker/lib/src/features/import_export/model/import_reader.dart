// Exception to shared words: the words a reader of a file's rows says of
// a line it leaves out are kept beside the rule that leaves it out.
// Exception to file length: the one reader of a file's rows, each kind
// of row (spending, refund, transfer, trade, invoice) a method of it that
// shares its state (the rows read so far, what was refunded of each).
part of 'import_export.dart';

/// A cell of the line being read, by its column ([ExchangeHeader.cell]).
typedef _Cell = String Function(ExchangeColumn column);

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

  /// The entries read by the 編號 the file gives them, for a refund later
  /// in the file to name.
  final _byFileId = <String, Entry>{};

  /// The entries read by the id each takes, for the spending a refund
  /// read names to be found, the book not having it yet.
  final _byId = <String, Entry>{};

  /// Refunds already given against spending in this file, by its id.
  final _refunded = <String, int>{};

  /// The group each 群組 written in the file is kept under in the book.
  final _groupOf = <String, String>{};
  final _problems = <String>[];

  /// The line of the file being read, and the id its entry takes.
  var _line = 1;
  var _id = '';
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
      nextCategoryColor(count),
      income: income,
    );
    _categories.add(made);
    _categoryByName[name] = made;
    return name;
  }

  /// The id the entry of a line takes: the 編號 [written], unless the
  /// trash holds an entry of it; a new one when none is written. Null,
  /// with why, when the line cannot be kept for it.
  (String?, String?) _idOf(String written) {
    if (written.isEmpty) return (book.newId(), null);
    if (book.entries.byId(written) != null) return (null, '帳本裡已經有這一筆');
    if (_byFileId.containsKey(written)) {
      return (null, importRepeatedIdWords(written));
    }
    return (book.inTrash(written) ? book.newId() : written, null);
  }

  /// The group the entries of the 群組 [written] are kept under: the one
  /// written while neither the book nor its trash has an entry of it, so
  /// an entry read never joins a group of the book (review 37 2); a new
  /// one otherwise, the same for every line of the file that writes it.
  String? _groupNamed(String written) {
    if (written.isEmpty) return null;
    return _groupOf[written] ??=
        book.entries.inGroup(written).isEmpty && !book.groupInTrash(written)
        ? written
        : book.newId();
  }

  /// Reads the [line] of the file; why it cannot be kept, or null when
  /// it was.
  String? read(_Cell cell, {required int line}) {
    _line = line;
    final read = ExchangeColumn.date.cell.read(
      cell(ExchangeColumn.date),
      latest: BusinessDate.of(latestEntryDay(book.today)),
    );
    if (read case DayRefused(:final problem)) return dayProblemWords(problem);
    final day = _utcDay(read)!;
    final LineKind? named;
    switch (ExchangeColumn.kind.cell.read(cell(ExchangeColumn.kind))) {
      case KindUnknown(:final words):
        return '不認得的類型「$words」';
      case KindNamed(:final kind):
        named = kind;
    }
    final dayTrade = ExchangeColumn.dayTrade.cell.read(
      cell(ExchangeColumn.dayTrade),
    );
    if (dayTrade == null) return importDayTradeWords;
    final LineMark? mark;
    switch (ExchangeColumn.mark.cell.read(cell(ExchangeColumn.mark))) {
      case MarkUnknown(:final words):
        return importMarkWords(words);
      case MarkNamed(mark: final named):
        mark = named;
    }
    final fileId = cell(ExchangeColumn.id);
    final (id, taken) = _idOf(fileId);
    if (taken != null) return taken;
    _id = id!;
    final account = _accountNamed(cell(ExchangeColumn.account));
    final from = _account(account);
    final (value, unreadable) = _cellAmount(
      cell,
      ExchangeColumn.amount,
      from.currency,
    );
    if (unreadable != null) return unreadable;
    final kind =
        named ??
        (value == null || value == 0
            ? null
            : value < 0
            ? LineKind.expense
            : LineKind.income);
    final stock = kind == LineKind.stock || kind == LineKind.split;
    if (kind == null || !stock && (value ?? 0) == 0) return importAmountWords;
    final amount = (value ?? 0).abs();
    final note = cell(ExchangeColumn.note);
    final entry = switch (kind) {
      LineKind.expense || LineKind.income => _cashFlow(
        cell,
        day,
        account,
        from,
        amount,
        note,
        income: kind == LineKind.income,
      ),
      LineKind.refund => _refund(cell, day, account, from, amount, note),
      LineKind.transfer => _transfer(cell, day, account, from, amount, note),
      _ => _investment(cell, kind, day, account, from, amount, note),
    };
    if (entry is! Entry) return entry as String;
    final recurring = cell(ExchangeColumn.recurring);
    final made = entry.withLinks(
      group: _groupNamed(cell(ExchangeColumn.group)),
      // A link to an item the book does not have is no link.
      recurring: book.recurring.byId(recurring) == null ? null : recurring,
      mark: _entryMark(mark),
      dayTrade: dayTrade,
    );
    // Checked as one typed in would be, with the accounts this file adds;
    // the shares its trades take are checked together when it is added.
    final original = made.refundOf == null
        ? null
        : _byId[made.refundOf!] ?? book.entries.byId(made.refundOf!);
    final failure = book.entryValidator.validate(
      made,
      holdings: false,
      opening: _accounts,
      refunding: original == null
          ? null
          : (original: original, left: _left(original)),
    );
    if (failure is MissingHomeAmount) return importMissingHomeWords;
    if (failure is RefundOtherCurrency || failure is RefundToOtherAccount) {
      return importRefundTargetWords(
        cell(ExchangeColumn.refundOf),
        validationMessage(failure!),
      );
    }
    if (failure is RefundExceedsRemaining) return importNoOriginalWords;
    if (failure != null) return validationMessage(failure);
    if (_already(book, made)) return '帳本裡已經有這一筆';
    if (made.isRefund) {
      _refunded[made.refundOf!] = (_refunded[made.refundOf!] ?? 0) + amount;
    }
    _found.add((_line, made));
    _byId[made.id] = made;
    if (fileId.isNotEmpty) _byFileId[fileId] = made;
    return null;
  }

  Object _cashFlow(
    _Cell cell,
    DateTime day,
    String account,
    Account from,
    int amount,
    String note, {
    required bool income,
  }) {
    final String category;
    var parts = const <(String, int)>[];
    switch (ExchangeColumn.category.cell.read(
      cell(ExchangeColumn.category),
      from.currency,
      split: !income,
    )) {
      case SplitUnreadable():
        return '拆分的金額看不懂';
      case OneCategory(:final name):
        category = _categoryNamed(name, income: income);
      // Parts that do not add up to the amount are the ledger's to
      // refuse, as a split typed in.
      case SplitCategory(parts: final written):
        parts = [
          for (final (name, part) in written)
            (_categoryNamed(name, income: false), part),
        ];
        category = parts.first.$1;
    }
    final (home, homeProblem) = _cellAmount(cell, ExchangeColumn.home);
    if (homeProblem != null) return homeProblem;
    final card = from.kind == AccountKind.card;
    return Entry(
      id: _id,
      date: day,
      type: income ? EntryType.income : EntryType.expense,
      amount: amount,
      account: account,
      category: category,
      parts: parts,
      note: note,
      merchant: income ? '' : cell(ExchangeColumn.merchant),
      tags: ExchangeColumn.tags.cell.read(cell(ExchangeColumn.tags)),
      installments: card && !income
          ? ExchangeColumn.installments.cell.read(
                  cell(ExchangeColumn.installments),
                ) ??
                0
          : 0,
      home: from.foreign
          ? home ?? book.marketData.toHome(amount, from.currency)
          : null,
    );
  }

  /// A refund of the spending its 退款對象 names, when the book or the
  /// file has it with that much left to give back; else of the latest
  /// spending on [account] up to [day] with that much left, the same
  /// shop's first. On a foreign account its worth at home is the 台幣金額
  /// written, when it is within what of the purchase's worth is left,
  /// else its share of the purchase's worth (D62), else the amount at
  /// today's rate.
  Object _refund(
    _Cell cell,
    DateTime day,
    String account,
    Account from,
    int amount,
    String note,
  ) {
    bool spending(Entry e) =>
        e.type == EntryType.expense && !e.isRefund && !e.date.isAfter(day);
    bool refundable(Entry e) => spending(e) && _left(e) >= amount;
    final shop = cell(ExchangeColumn.merchant);
    final named = cell(ExchangeColumn.refundOf);
    final Entry? linked = named.isEmpty
        ? null
        : _byFileId[named] ?? book.entries.byId(named);
    final Entry original;
    if (linked != null) {
      // What is left of it to give back is weighed by the write rules,
      // once they know it goes back to an account that can take it.
      if (!spending(linked)) return importNoOriginalWords;
      original = linked;
    } else {
      final candidates = [
        // Exception to as-of-today: a duplicate check looks at every entry
        // written.
        for (final e in [...book.entries.all, for (final (_, f) in _found) f])
          if (e.account == account && refundable(e)) e,
      ]..sort((a, b) => b.date.compareTo(a.date));
      if (candidates.isEmpty) return importNoOriginalWords;
      original = candidates.firstWhere(
        (e) => shop.isNotEmpty && e.merchant == shop,
        orElse: () => candidates.first,
      );
    }
    // As the composer writes it: the purchase's split and tags (D65).
    final earlier = [
      ...book.entries.refundsOf(original.id),
      for (final (_, f) in _found)
        if (f.refundOf == original.id) f,
    ];
    final share = refundShare(original, amount, earlier: earlier);
    final (typed, homeProblem) = _cellAmount(cell, ExchangeColumn.home);
    if (homeProblem != null) return homeProblem;
    int? home;
    if (from.foreign) {
      // What of the purchase's worth is not yet given back: a refund of
      // all that is left takes all of it.
      final left = refundShare(
        original,
        original.amount,
        earlier: earlier,
      ).home;
      if (typed != null && typed <= 0) return refundHomeWords(null);
      if (typed != null && left != null && typed > left) {
        return refundHomeWords(left);
      }
      home =
          typed ?? share.home ?? book.marketData.toHome(amount, from.currency);
    }
    return Entry(
      id: _id,
      date: day,
      type: EntryType.income,
      amount: amount,
      account: account,
      category: share.category,
      note: note,
      tags: share.tags,
      parts: share.parts,
      refundOf: original.id,
      home: home,
    );
  }

  int _left(Entry e) {
    final inBook = book.entries.byId(e.id) == null
        ? e.amount
        : book.entryQueryService.refundable(e);
    return inBook - (_refunded[e.id] ?? 0);
  }

  Object _transfer(
    _Cell cell,
    DateTime day,
    String account,
    Account from,
    int amount,
    String note,
  ) {
    final into = cell(ExchangeColumn.into);
    if (into.isEmpty) return '轉帳要填轉入帳戶';
    final to = _accountNamed(into);
    final target = _account(to);
    if (from.kind == AccountKind.card) return '信用卡不能轉出，請記成支出';
    final (charged, feeProblem) = _cellAmount(cell, ExchangeColumn.fee);
    final (received, receivedProblem) = target.currency == from.currency
        ? (null, null)
        : _cellAmount(cell, ExchangeColumn.received, target.currency);
    if (feeProblem ?? receivedProblem case final why?) return why;
    final fee = charged ?? 0;
    if (target.kind == AccountKind.card && fee > 0) return '繳卡費不能有手續費';
    if (fee > 0 && from.foreign) return '外幣帳戶轉出不能記手續費';
    return TransferDrafts.between(
      id: _id,
      date: day,
      amount: amount,
      from: account,
      note: note,
      to: to,
      fee: fee,
      received: received,
    );
  }

  Object _investment(
    _Cell cell,
    LineKind kind,
    DateTime day,
    String account,
    Account from,
    int amount,
    String note,
  ) {
    final code = cell(ExchangeColumn.code).toUpperCase();
    if (code.isEmpty) return '投資要填股票代號';
    if (from.kind == AccountKind.card) return '投資不能用信用卡';
    final shares =
        ExchangeColumn.shares.cell.read(cell(ExchangeColumn.shares)) ?? 0;
    final needsShares = kind != LineKind.cash;
    if (needsShares && shares <= 0) return '請填股數';
    final trade = kind == LineKind.buy || kind == LineKind.sell;
    final (fee, feeProblem) = trade
        ? _cellAmount(cell, ExchangeColumn.fee)
        : (null, null);
    final (tax, taxProblem) = kind == LineKind.cut
        ? (null, null)
        : _cellAmount(cell, ExchangeColumn.tax);
    if (feeProblem ?? taxProblem case final why?) return why;
    return Entry(
      id: _id,
      date: day,
      type: switch (kind) {
        LineKind.buy => EntryType.buy,
        LineKind.sell => EntryType.sell,
        _ => EntryType.dividend,
      },
      amount: amount,
      account: account,
      category: trade ? investmentCategory : dividendCategory,
      note: note,
      holding: code,
      shares: switch (kind) {
        LineKind.cash => 0,
        LineKind.cut => -shares,
        _ => shares,
      },
      fee: fee ?? 0,
      tax: tax ?? 0,
      split: kind == LineKind.split,
      average:
          kind == LineKind.sell &&
          ExchangeColumn.costing.cell.read(cell(ExchangeColumn.costing)),
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
    // Each trade checked after the book and those read before it.
    final trades = book.entryValidator.tradeRun();
    final used = <String>{};
    final cats = <String>{};
    for (final i in days.expand((day) => byDay[day]!)) {
      final (line, e) = _found[i];
      yield null;
      if (e.isInvestment) {
        // Only a sale or a reduction can leave a stock short of shares.
        final takes = e.type == EntryType.sell || e.isReduction;
        if (takes && !trades.holds(e)) {
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

/// Spending from a Ministry of Finance e-invoice file, read by the one
/// reader of them ([readInvoiceFile]): the 消費明細 CSV, with a 發票號碼
/// column, or a carrier's M and D lines. Each invoice becomes spending on
/// [account] at the shop, noted with its invoice number; void ones and
/// invoices already in the book are left out, and so is one the reader
/// refuses, named. What is left out is listed in the order of the file.
Import importInvoices(ImportBook book, String text, {required String account}) {
  final found = _invoices(book, text, account: account);
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

/// The invoices of [text] as spending on [account], those the reader
/// refuses or the book has already left out, with why, by their lines.
/// A CSV row the reader cannot read leaves the whole file out.
Import _invoices(ImportBook book, String text, {required String account}) {
  final EInvoiceFile file;
  try {
    file = readInvoiceFile(
      text,
      latest: BusinessDate.of(latestEntryDay(book.today)),
    );
  } on FormatException {
    // Said to the person as a problem of the file.
    return const Import([], 1, problems: ['檔案格式看不懂']);
  }
  final entries = <Entry>[];
  final left = <(int, String)>[
    for (final (:number, :seller, :line, :why) in file.refused)
      (line, '${number.isEmpty ? seller : number}：${invoiceRefusalWords(why)}'),
  ];
  for (final invoice in file.invoices) {
    final BusinessDate(:year, :month, :day) = invoice.date;
    final date = DateTime.utc(year, month, day);
    final number = invoice.number;
    final value = invoice.amount.minorUnits.toInt();
    // The file holds each number once (readInvoiceFile).
    if (value <= 0 ||
        hasInvoice(
          book.entries,
          date,
          number,
          shop: invoice.seller,
          amount: value,
        )) {
      final why = value <= 0 ? importAmountWords : importAlreadyWords;
      left.add((
        invoice.line,
        '${number.isEmpty ? invoice.seller : number}：$why',
      ));
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
  final byLine = [...left.indexed]
    ..sort((a, b) {
      final at = a.$2.$1.compareTo(b.$2.$1);
      return at != 0 ? at : a.$1.compareTo(b.$1);
    });
  return Import(
    entries,
    left.length,
    problems: [for (final (_, (_, why)) in byLine) why],
  );
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
