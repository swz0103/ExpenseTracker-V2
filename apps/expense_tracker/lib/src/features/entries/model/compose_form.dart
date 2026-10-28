import '../../../core/ledger/amounts.dart';
import '../../../core/ledger/checks.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ledger/trading.dart';

/// The kinds of record the composer makes. 代墊 has no tab of its own:
/// it is picked inside 支出 (paid for someone) or 收入 (paid back).
enum ComposeMode {
  expense('支出'),
  income('收入'),
  transfer('轉帳'),
  lend('代墊'),
  investment('投資');

  const ComposeMode(this.label);

  final String label;

  static ComposeMode of(EntryType type) => switch (type) {
    EntryType.expense => expense,
    EntryType.income => income,
    EntryType.transfer => transfer,
    _ => investment,
  };
}

/// What 記一筆 holds while it is being filled in, and the entry it makes:
/// every field, the choices each tab starts with, and the rules that tie
/// fields together (a trade's amount from shares and price, a split that
/// must add up, the fee and tax a trade suggests). The screen only shows
/// it and passes on what is tapped, so all of this is tested without one.
final class ComposeForm {
  /// A form for a new entry of [type], filled in from [draft] if given;
  /// to change [editing]; or to refund [refunded].
  ComposeForm(
    this.ledger, {
    required EntryType type,
    this.editing,
    this.draft,
    this.refunded,
  }) {
    mode = ComposeMode.of(type);
    trade = type.index >= EntryType.buy.index ? type : EntryType.buy;
    fresh();
    final source = editing ?? draft;
    final editingNow = editing;
    if (editingNow != null) receipt = ledger.receiptOf(editingNow.id);
    final refundedNow = refunded;
    if (source != null) {
      load(source);
      findLending(source);
    } else if (refundedNow != null) {
      mode = ComposeMode.income;
      amount = ledger.refundable(refundedNow);
      account = refundedNow.account;
      category = refundedNow.category;
    }
  }

  final Ledger ledger;

  /// The entry being changed, if any.
  final Entry? editing;

  /// A new entry's starting values, such as a card payment.
  final Entry? draft;

  /// The spending being refunded, for a refund.
  final Entry? refunded;

  late ComposeMode mode;
  late EntryType trade;
  late int amount;
  late DateTime date;
  late String account;
  late String to;
  late String category;
  String? holding;
  late int shares;
  var price = 0.0;
  var merchant = '';
  var tags = <String>[];
  var note = '';

  /// The parts of a split, or null when the whole goes to [category].
  List<(String, int)>? parts;
  var fee = 0;

  /// What a foreign amount is worth in NT$, and what a transfer between
  /// currencies delivers, as typed; null works them out at today's rate.
  int? home;
  int? received;

  /// The 二代健保 premium withheld from a cash dividend, as typed; null
  /// works it out from the amount and day.
  int? premium;
  var installments = 0;
  var average = false;
  var splitShares = false;

  /// A dividend that changes the shares held, opened from its link: most
  /// dividends are cash only.
  var shareChange = false;

  /// A capital reduction: the shares go down and cash comes back.
  var reduce = false;

  /// 代墊: money coming back from the person rather than paid for them.
  var back = false;

  /// The receipt photo's file name; null when none.
  String? receipt;

  /// Shows the merchant, tags and note: hidden until asked for, or until
  /// an entry that has them is opened, so a quick entry stays short.
  var more = false;

  /// A trade's broker fee and tax as typed, or as it was saved; null
  /// takes the suggestion.
  int? tradeFee;
  int? tradeTax;

  /// Puts [entry]'s values in the fields.
  void load(Entry entry) {
    amount = entry.amount;
    date = entry.date;
    account = entry.account;
    to = entry.to ?? to;
    category = entry.category.isEmpty ? category : entry.category;
    holding = entry.holding ?? holding;
    shares = entry.shares;
    price = entry.shares == 0 ? 0 : entry.amount / entry.shares;
    note = entry.note;
    merchant = entry.merchant;
    tags = [...entry.tags];
    more =
        entry.merchant.isNotEmpty ||
        entry.tags.isNotEmpty ||
        entry.note.isNotEmpty;
    parts = entry.parts.isEmpty ? null : [...entry.parts];
    fee = entry.type == EntryType.transfer ? entry.fee : 0;
    home = entry.home;
    received = entry.received;
    premium = entry.type == EntryType.dividend ? entry.tax : null;
    installments = entry.installments;
    average = entry.average;
    splitShares = entry.split;
    shareChange = entry.type == EntryType.dividend && entry.shares != 0;
    reduce = entry.isReduction;
    if (reduce) shares = -entry.shares;
    if (entry.type == EntryType.buy || entry.type == EntryType.sell) {
      tradeFee = entry.fee;
      tradeTax = entry.tax;
    }
  }

  /// The accounts a form may start on: the open ones, or every one when
  /// all are archived (the composer makes sure there is an open one
  /// first, but a form put aside may outlive it).
  List<Account> get startAccounts {
    final open = ledger.openAccounts;
    return open.isNotEmpty ? open : ledger.accounts;
  }

  /// Empty fields with sensible first choices for the current tab.
  void fresh() {
    final accounts = startAccounts;
    amount = 0;
    date = ledger.today;
    account = accounts.first.id;
    to = accounts.length > 1 ? accounts[1].id : accounts.first.id;
    final common = categoryChoices();
    category = common.isEmpty ? '' : common.first;
    holding = ledger.holdings.isEmpty ? null : ledger.holdings.first.code;
    shares = 0;
    price = 0;
    note = '';
    merchant = '';
    tags = [];
    parts = null;
    fee = 0;
    tradeFee = null;
    tradeTax = null;
    home = null;
    received = null;
    premium = null;
    installments = 0;
    average = false;
    splitShares = false;
    shareChange = false;
    reduce = false;
    back = false;
    receipt = null;
    if (mode == ComposeMode.lend) {
      // Paid from the main account, for the first person owing.
      final main = ledger.mainAccount;
      if (main.isNotEmpty) account = main;
      to = people.isEmpty ? '' : people.first.id;
    }
  }

  /// Opens a transfer to or from someone's account as 代墊 or 還款.
  void findLending(Entry entry) {
    if (entry.type != EntryType.transfer) return;
    final other = entry.to;
    if (other == null) return;
    if (ledger.account(other).kind == AccountKind.receivable) {
      mode = ComposeMode.lend;
      back = false;
    } else if (ledger.account(entry.account).kind == AccountKind.receivable) {
      // Saved from the person to the account; the form keeps the person
      // in [to] either way.
      mode = ComposeMode.lend;
      back = true;
      account = other;
      to = entry.account;
    }
  }

  /// The tab showing: 代墊 sits under 支出, 還款 under 收入.
  ComposeMode get tab => switch (mode) {
    ComposeMode.lend => back ? ComposeMode.income : ComposeMode.expense,
    final mode => mode,
  };

  /// The tabs along the top.
  static const tabs = [
    ComposeMode.expense,
    ComposeMode.income,
    ComposeMode.transfer,
    ComposeMode.investment,
  ];

  /// 代墊 from the expense tab, 對方還錢 from the income tab; the amount,
  /// date and notes stay.
  void lend({required bool back}) {
    mode = ComposeMode.lend;
    this.back = back;
    parts = null;
    installments = 0;
    final main = ledger.mainAccount;
    if (main.isNotEmpty) account = main;
    final known = {for (final a in people) a.id};
    if (!known.contains(to)) to = people.isEmpty ? '' : people.first.id;
  }

  /// A category picked: back to a plain expense or income from 代墊.
  void pickCategory(String name) {
    mode = tab;
    category = name;
  }

  /// A merchant picked: on a new entry, the category it was last filed
  /// under comes with it (unless split), and the account it was paid
  /// from, while that account is open and in the same currency.
  void pickMerchant(String name) {
    merchant = name;
    if (editing != null) return;
    final last = ledger.lastAt(name);
    if (last == null) return;
    if (parts == null) category = last.category;
    _accountFrom(last);
  }

  /// [entry]'s account, when it is open and keeps the same currency as
  /// the one chosen, so an amount typed stays in its unit.
  void _accountFrom(Entry entry) {
    final open = {for (final a in ledger.openAccounts) a.id};
    if (!open.contains(entry.account)) return;
    if (ledger.account(entry.account).currency != currency) return;
    account = entry.account;
  }

  /// Starts a new expense from [entry], one of [Ledger.usual]: its
  /// category, merchant, account and amount, on today.
  void startFrom(Entry entry) {
    category = entry.category;
    merchant = entry.merchant;
    if (entry.merchant.isNotEmpty) more = true;
    final open = {for (final a in ledger.openAccounts) a.id};
    if (open.contains(entry.account)) account = entry.account;
    // The amount only in its own unit.
    if (ledger.account(entry.account).currency == currency) {
      setAmount(entry.amount);
    }
  }

  /// The accounts that keep what someone owes, one per person.
  List<Account> get people => [
    for (final a in ledger.openAccounts)
      if (a.kind == AccountKind.receivable) a,
  ];

  /// Categories of this tab, the most used lately first.
  List<String> categoryChoices() =>
      ledger.categoriesByUse(income: tab == ComposeMode.income);

  /// Brings back a form put aside: [entry] with its receipt photo, on
  /// accounts still open; when none is open, its own accounts stay.
  void restore(Entry entry, String? photo) {
    load(entry);
    findLending(entry);
    if (entry.isInvestment) trade = entry.type;
    receipt = photo;
    final accounts = ledger.openAccounts;
    final open = {for (final a in accounts) a.id};
    if (!open.contains(account) && accounts.isNotEmpty) {
      account = accounts.first.id;
    }
    if (!open.contains(to)) to = account;
  }

  /// Moves to the tab [next] with fresh fields, keeping a receipt photo
  /// already chosen: the photo is of what was bought or paid, whichever
  /// kind of entry it turns out to be.
  void switchTo(ComposeMode next) {
    final photo = receipt;
    mode = next;
    fresh();
    receipt = photo;
  }

  /// A new amount typed: what was worked out from the old one goes.
  void setAmount(int value) {
    amount = value;
    home = null;
    received = null;
    premium = null;
    if (trading && shares > 0) price = value / shares;
  }

  /// The shares of a trade: the amount follows at the same price.
  void setShares(int value) {
    shares = value;
    if (trading) amount = (shares * price).round();
  }

  /// The price of a trade: the amount follows for the same shares.
  void setPrice(double value) {
    price = value;
    if (trading) amount = (shares * price).round();
  }

  EntryType get type => switch (mode) {
    ComposeMode.expense => EntryType.expense,
    ComposeMode.income => EntryType.income,
    ComposeMode.transfer || ComposeMode.lend => EntryType.transfer,
    ComposeMode.investment => trade,
  };

  /// The sign written before the amount.
  String get sign => switch (type) {
    _ when amount == 0 => '',
    EntryType.expense || EntryType.buy => '−',
    EntryType.transfer => '',
    _ => '+',
  };

  /// A buy or sale, whose amount comes from shares and price.
  bool get trading =>
      mode == ComposeMode.investment && trade != EntryType.dividend;

  bool get onCard =>
      type == EntryType.expense &&
      ledger.account(account).kind == AccountKind.card;

  /// A transfer with a fee field: from an NT$ account, whose fee counts
  /// as NT$ spending, and not to a card, whose payment carries none.
  bool get takesFee =>
      currency == homeCode && ledger.account(to).kind != AccountKind.card;

  /// The currency of the account paying or receiving, and of a
  /// transfer's receiving account.
  String get currency => ledger.account(account).currency;
  String get toCurrency => ledger.account(to).currency;

  /// Spending or income in a foreign-currency account, which also needs
  /// its worth in NT$.
  bool get foreign =>
      currency != homeCode &&
      (type == EntryType.expense || type == EntryType.income);

  /// A transfer between accounts kept in different currencies.
  bool get crossing => type == EntryType.transfer && currency != toCurrency;

  /// [home], else the refunded share of the purchase's worth, else the
  /// amount at today's rate; null without a rate.
  int? get homeValue {
    final typed = home;
    if (typed != null) return typed;
    final original = refunded;
    final worth = original?.home;
    if (original != null && worth != null && original.amount > 0) {
      return (worth * amount / original.amount).round();
    }
    return ledger.toHome(amount, currency);
  }

  /// [received], else the amount at today's rates.
  int? get receivedValue =>
      received ?? ledger.convert(amount, currency, toCurrency);

  /// The premium withheld from the cash dividend being written.
  int get withheld => premium ?? dividendPremium(amount, date);

  /// The broker's fee and tax the ledger's Taiwan rules suggest for the
  /// trade being written.
  (int, int) get suggested {
    final tax = type == EntryType.sell
        ? saleTax(holding ?? '', amount, shares, date)
        : 0;
    return (brokerFee(amount, shares), tax);
  }

  /// The trade's fee and tax: as typed, else as suggested.
  (int, int) get charges {
    if (type != EntryType.buy && type != EntryType.sell) return (0, 0);
    final (fee, tax) = suggested;
    return (tradeFee ?? fee, tradeTax ?? tax);
  }

  /// What a trade settles at: paid for a buy with its fee, received for a
  /// sale less fee and tax.
  int get settlement {
    final (fee, tax) = charges;
    return trade == EntryType.sell ? amount - fee - tax : amount + fee;
  }

  /// Splits the amount into parts, or puts it back into one.
  void toggleSplit() {
    parts = parts == null ? [(category, amount)] : null;
  }

  /// Shares the amount evenly over the parts; the last takes what is
  /// left over.
  void evenly() {
    final now = parts;
    if (now == null || now.isEmpty) return;
    final each = amount ~/ now.length;
    parts = [
      for (final (i, (name, _)) in now.indexed)
        (name, i == now.length - 1 ? amount - each * (now.length - 1) : each),
    ];
  }

  /// Adds a part for [name] with what is not yet shared out.
  void addPart(String name) {
    final now = parts ?? [];
    final used = now.fold(0, (sum, p) => sum + p.$2);
    parts = [...now, (name, amount - used)];
  }

  /// Changes the part at [index] to [value]; zero takes it away.
  void setPart(int index, int value) {
    final now = parts;
    if (now == null) return;
    parts = [
      for (final (i, p) in now.indexed)
        if (i != index) p else if (value > 0) (p.$1, value),
    ];
  }

  /// Moving between a trade and a dividend starts the shares afresh: a
  /// dividend's are the ones it adds.
  void changeTrade(EntryType next) {
    if ((next == EntryType.dividend) != (trade == EntryType.dividend)) {
      shares = 0;
      amount = 0;
      splitShares = false;
      shareChange = false;
      reduce = false;
    }
    tradeFee = null;
    tradeTax = null;
    trade = next;
  }

  /// The parts of a split being written; none for a foreign amount.
  List<(String, int)>? get splitParts =>
      type == EntryType.expense && !foreign ? parts : null;

  /// A dividend that changes the shares held: a stock dividend, a split
  /// or, with [reduce], a capital reduction.
  bool get stock => type == EntryType.dividend && shares > 0;
  bool get reducing => stock && reduce;

  /// Why the entry cannot be kept yet; null when it can. The ledger's
  /// own checks, and a split that must add up to the amount.
  String? get problem {
    if (mode == ComposeMode.lend && to.isEmpty) return '請選擇代墊對象';
    final found = ledger.problemWith(build(), replacing: editing);
    if (found != null) return found;
    final splitTotal = splitParts?.fold(0, (sum, p) => sum + p.$2);
    if (splitTotal != null && splitTotal != amount) {
      return '拆分的金額要等於總額（差 ${groupDigits(amount - splitTotal)}）';
    }
    return null;
  }

  bool get lendingBack => mode == ComposeMode.lend && back;

  /// The entry as the form now stands.
  Entry build() {
    final kind = type;
    final split = splitParts;
    final (tradeFee, tradeTax) = charges;
    return Entry(
      id: editing?.id ?? ledger.newId(),
      date: date,
      type: kind,
      amount: amount,
      // Paid back: from the person's account into the chosen one.
      account: lendingBack ? to : account,
      category: switch (kind) {
        EntryType.transfer => transferCategory,
        EntryType.dividend => '股息收入',
        EntryType.buy || EntryType.sell => '投資',
        _ => split == null || split.isEmpty ? category : split.first.$1,
      },
      note: note.trim(),
      to: lendingBack
          ? account
          : kind == EntryType.transfer
          ? to
          : null,
      holding: mode == ComposeMode.investment ? holding : null,
      shares: mode != ComposeMode.investment
          ? 0
          : reducing
          ? -shares
          : shares,
      recurring: editing?.recurring ?? draft?.recurring,
      merchant: kind == EntryType.expense ? merchant : '',
      tags: kind == EntryType.expense || kind == EntryType.income ? tags : [],
      parts: split != null && split.length > 1 ? split : const [],
      fee: kind == EntryType.transfer ? (takesFee ? fee : 0) : tradeFee,
      tax: kind == EntryType.dividend ? (reducing ? 0 : withheld) : tradeTax,
      refundOf: refunded?.id ?? editing?.refundOf,
      installments: onCard ? installments : 0,
      average: kind == EntryType.sell && average,
      split: stock && splitShares && !reducing,
      home: foreign ? homeValue : null,
      received: crossing ? receivedValue : null,
    );
  }
}
