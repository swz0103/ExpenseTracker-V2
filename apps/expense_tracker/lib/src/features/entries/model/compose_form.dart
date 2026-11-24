// Exception to models take what they use: the entry form is the page's
// whole state and reads eleven parts of the ledger (ADR-0013).

import 'package:core/foundation_values.dart'
    show BusinessDate, BusinessDayAnswer;
import 'package:core/money/price.dart' show timesPrice;
import 'package:ledger_trade_costs/calc/settlement.dart';
import 'package:ledger_trade_costs/model/trade_values.dart' show TradeKind;

import '../../../../design_system/display/amount.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/messages/validation_messages.dart';
import 'compose_form_refund.dart';
import 'invoices.dart';
import 'invoice_qr.dart';
import '../../../core/ledger/trading.dart';
import '../../../core/formatting/words.dart';
export 'compose_form_refund.dart' show RefundFields;

part 'compose_form_extras.dart';
part 'compose_form_lending.dart';
part 'compose_form_split.dart';
part 'compose_form_trade.dart';
part 'compose_form_transfer.dart';

/// The kinds of record the composer makes. 代墊 has no tab of its own:
/// it is picked inside 支出 (paid for someone) or 收入 (paid back).
enum ComposeMode {
  expense(Words.expense),
  income(Words.income),
  transfer(Words.transfer),
  lend(Words.lend),
  investment(Words.investment);

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
    Entry? refunded,
    this.brokerDiscount = defaultBrokerDiscount,
  }) : refunded = refunded ?? ledger.entryQueryService.originalOf(draft) {
    mode = ComposeMode.of(type);
    trade = type.index >= EntryType.buy.index ? type : EntryType.buy;
    fresh();
    final source = editing ?? draft;
    final editingNow = editing;
    if (editingNow != null) receipt = ledger.receipts.of(editingNow.id);
    final refundedNow = refunded;
    if (editing != null && editing!.group != null) {
      loadGroup(editing!);
    } else if (source != null) {
      load(source);
      findLending(source);
    } else if (refundedNow != null) {
      mode = ComposeMode.income;
      amount = ledger.entryQueryService.refundable(refundedNow);
      account = refundedNow.account;
      category = refundedNow.category;
    }
  }

  final Ledger ledger;

  /// The entry being changed, if any.
  final Entry? editing;

  /// A new entry's starting values, such as a card payment.
  final Entry? draft;

  /// The spending refunded: given, or named by the draft taken up (D79).
  Entry? refunded;

  /// The phone-wide broker's discount, in basis points of the full fee:
  /// the preference 券商手續費折扣, for a trade's account without its own.
  final int brokerDiscount;

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

  /// What the entry is besides its type (D52): a card's cashback or
  /// annual fee as the card page starts it, an e-invoice scanned; kept
  /// through an edit.
  EntryMark? mark;

  /// The parts of a split, or null when the whole goes to [category].
  List<(String, int)>? parts;

  /// What was paid in a spending for others, by person (the account that
  /// keeps what they owe), or null when none was; the rest is one's own.
  /// Kept apart from [parts]: a spending is split or paid for others,
  /// not both.
  List<(String, int)>? lent;

  /// The entries the form was opened from when they were written as one,
  /// by id, so a change keeps their ids: the spending's, and each
  /// person's.
  final _ids = <String>{};
  String? _ownId;
  final _lentIds = <String, String>{};

  /// Paid wholly for the one person in [lent] (opened from 幫忙付): their
  /// share follows the amount typed, rather than half of it.
  var _lentWhole = false;

  /// The sums someone paid back is made of, by entry, while 對方還錢.
  Set<String> paying = {};
  String? _group;
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

  /// A sale that is a day trade (當日沖銷), as the entry being changed
  /// was kept: no field shows it yet (D6), but it is kept, and its tax
  /// suggested at the day-trade rate.
  var dayTrade = false;
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

  /// A trade's broker fee and tax as the person typed them; null while
  /// untouched, which takes the suggestion and so follows every change of
  /// shares, price, stock or day. A saved value equal to what was
  /// suggested for it is read as untouched.
  int? tradeFee;
  int? tradeTax;

  /// Puts [entry]'s values in the fields.
  void load(Entry entry) {
    mark = entry.mark;
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
    dayTrade = entry.dayTrade;
    splitShares = entry.split;
    shareChange = entry.type == EntryType.dividend && entry.shares != 0;
    reduce = entry.isReduction;
    if (reduce) shares = -entry.shares;
    if (entry.type == EntryType.buy || entry.type == EntryType.sell) {
      // Charges still at what the rules suggested were never typed: they
      // follow the trade when it changes. Others were, and stay.
      final (fee, tax) = _suggestedFor(
        entry.type,
        entry.holding ?? '',
        entry.amount,
        entry.shares,
        entry.date,
        entry.dayTrade,
      );
      tradeFee = entry.fee == fee ? null : entry.fee;
      tradeTax = entry.tax == tax ? null : entry.tax;
    }
  }

  /// The accounts a form may start on: the open ones, or every one when
  /// all are archived (the composer makes sure there is an open one
  /// first, but a form put aside may outlive it).
  List<Account> get startAccounts {
    final open = ledger.accounts.open;
    return open.isNotEmpty ? open : ledger.accounts.all;
  }

  /// Empty fields with sensible first choices for the current tab.
  void fresh() {
    mark = null;
    final accounts = startAccounts;
    amount = 0;
    date = ledger.today;
    account = accounts.first.id;
    to = accounts.length > 1 ? accounts[1].id : accounts.first.id;
    final common = categoryChoices();
    category = common.isEmpty ? '' : common.first;
    holding = ledger.holdings.all.isEmpty
        ? null
        : ledger.holdings.all.first.code;
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
    dayTrade = false;
    splitShares = false;
    shareChange = false;
    reduce = false;
    back = false;
    receipt = null;
    lent = null;
    _lentWhole = false;
    if (mode == ComposeMode.lend) {
      // Paid from the main account, for the first person owing.
      final main = ledger.accounts.main;
      if (main.isNotEmpty) account = main;
      to = people.isEmpty ? '' : people.first.id;
    }
  }

  /// The tabs along the top.
  static const tabs = [
    ComposeMode.expense,
    ComposeMode.income,
    ComposeMode.transfer,
    ComposeMode.investment,
  ];

  /// A category picked: from 代墊's own tab (paying for someone, or
  /// their paying back) back to a plain expense or income. A spending
  /// shared with someone stays shared; only its category changes.
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
    final last = ledger.entryQueryService.lastAt(name);
    if (last == null) return;
    if (parts == null) category = last.category;
    _accountFrom(last);
  }

  /// [entry]'s account, when it is open and keeps the same currency as
  /// the one chosen, so an amount typed stays in its unit.
  void _accountFrom(Entry entry) {
    final open = {for (final a in ledger.accounts.open) a.id};
    if (!open.contains(entry.account)) return;
    if (ledger.account(entry.account).currency != currency) return;
    account = entry.account;
  }

  /// Fills a new expense from a scanned paper e-invoice: its day and total,
  /// its items and number in the note, tagged 發票, and a category guessed
  /// from the items; the merchant is left to pick, which brings its usual
  /// category and account.
  void fillInvoice(InvoiceQr invoice) {
    date = invoice.date;
    note = invoice.note;
    if (!tags.contains(Words.invoice)) tags = [...tags, Words.invoice];
    mark = EntryMark.invoice;
    more = true;
    category = guessCategory(
      ledger.entryQueryService,
      ledger.categories,
      merchant,
      [for (final item in invoice.items) item.name].join(' '),
    );
    // An invoice is in NT$: on an account in another currency, the first
    // open one in NT$ pays it.
    if (currency != homeCode) {
      for (final a in ledger.accounts.open) {
        if (a.currency == homeCode) {
          account = a.id;
          break;
        }
      }
    }
    setAmount(invoice.total);
  }

  /// Starts a new expense from [entry], one of `EntryQueryService.usual`: its
  /// category, merchant, account and amount, on today.
  void startFrom(Entry entry) {
    category = entry.category;
    merchant = entry.merchant;
    if (entry.merchant.isNotEmpty) more = true;
    final open = {for (final a in ledger.accounts.open) a.id};
    if (open.contains(entry.account)) account = entry.account;
    // The amount only in its own unit.
    if (ledger.account(entry.account).currency == currency) {
      setAmount(entry.amount);
    }
  }

  /// The accounts that keep what someone owes, one per person.
  List<Account> get people => [
    for (final a in ledger.accounts.open)
      if (a.kind == AccountKind.receivable) a,
  ];

  /// Categories of this tab, the most used lately first.
  List<String> categoryChoices() =>
      ledger.reportService.categoriesByUse(income: tab == ComposeMode.income);

  /// Brings back a form put aside ([entry], its photo), on open accounts.
  void restore(Entry entry, String? photo) {
    refunded = ledger.entryQueryService.originalOf(entry) ?? refunded;
    load(entry);
    findLending(entry);
    if (entry.isInvestment) trade = entry.type;
    receipt = photo;
    final accounts = ledger.accounts.open;
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
    // Shares still even follow the new amount; those typed stay.
    final split = lent;
    if (_lentWhole && split != null && split.length == 1) {
      lent = [(split.first.$1, value)];
    } else if (split != null &&
        split.every((p) => p.$2 == split.first.$2) &&
        split.first.$2 == amount ~/ (split.length + 1)) {
      final share = value ~/ (split.length + 1);
      lent = [for (final (p, _) in split) (p, share)];
    }
    amount = value;
    home = null;
    received = null;
    premium = null;
    if (trading && shares > 0) price = value / shares;
  }

  /// The shares of a trade: the amount follows at the same price.
  void setShares(int value) {
    shares = value;
    if (trading) amount = timesPrice(shares, price);
  }

  /// The price of a trade: the amount follows for the same shares.
  void setPrice(double value) {
    price = value;
    if (trading) amount = timesPrice(shares, price);
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

  /// [received], else the amount at today's rates.
  int? get receivedValue =>
      received ?? ledger.marketData.convert(amount, currency, toCurrency);

  /// The premium withheld from the cash dividend being written.
  int get withheld => premium ?? dividendPremium(amount, date);

  /// Why the entry cannot be kept yet; null when it can: the ledger's
  /// write rules, which the save asks again, on the entry as it stands
  /// (a split of one part included, though it is kept as no split).
  String? get problem {
    if (mode == ComposeMode.lend && to.isEmpty) return '請選擇代墊對象';
    if (lending) return _lendingProblem;
    final found = ledger.entryValidator.validate(
      build(wholeSplit: true),
      replacing: editing,
    );
    return found == null ? null : validationMessage(found);
  }

  /// The key of the entry [warning] was last worked out for, and what it
  /// said (compose_form_trade.dart).
  String? _warnedFor;
  String? _warned;

  String? get _lendingProblem {
    if (amount <= 0) return '請輸入金額';
    if (lent!.any((p) => p.$2 <= 0)) return '代墊的金額要大於 0';
    if (own < 0) return '代墊的金額超過總額（多 ${groupDigits(-own)}）';
    for (final e in buildAll()) {
      final was = ledger.entries.byId(e.id);
      final found = ledger.entryValidator.validate(e, replacing: was);
      if (found != null) return validationMessage(found);
    }
    return null;
  }

  bool get lendingBack => mode == ComposeMode.lend && back;

  /// The entries the form makes: the one of [build], or, paying for
  /// others, one's own spending (none when nothing of it is one's own)
  /// and a transfer to each person, written as one.
  List<Entry> buildAll() {
    final shares = lent;
    if (!lending || shares == null) return [build()];
    final made = <Entry>[];
    final group = _group ?? ledger.newId();
    final mine = own;
    if (mine > 0) {
      final opened = editing;
      final ownId =
          _ownId ??
          (opened != null && !_lentIds.containsValue(opened.id)
              ? opened.id
              : ledger.newId());
      made.add(build().inGroup(null, id: ownId, amount: mine));
    }
    for (final (person, value) in shares) {
      made.add(
        Entry(
          id: _lentIds[person] ?? ledger.newId(),
          date: date,
          type: EntryType.transfer,
          amount: value,
          account: account,
          category: transferCategory,
          note: note.trim(),
          to: person,
        ),
      );
    }
    // One alone needs no group: all of it paid for one person is a
    // transfer to them, as 代墊 always was.
    if (made.length < 2) return made;
    return [for (final e in made) e.inGroup(group)];
  }

  /// The entry as the form now stands. A split of one part is kept as
  /// none, unless [wholeSplit], for its part to be checked.
  Entry build({bool wholeSplit = false}) {
    final kind = type;
    final refund = refundBeingWritten;
    final split = refund == null ? splitParts : refund.parts;
    final (tradeFee, tradeTax) = charges;
    return Entry(
      id: editing?.id ?? ledger.newId(),
      date: date,
      type: kind,
      amount: amount,
      // Paid back: from the person's account into the chosen one.
      account: lendingBack ? to : account,
      category: switch (kind) {
        EntryType.transfer => keptCategory(kind, editing?.category ?? ''),
        EntryType.dividend => dividendCategory,
        EntryType.buy || EntryType.sell => investmentCategory,
        _ when refund != null => refund.category,
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
      tags: refund != null
          ? refund.tags
          : kind == EntryType.expense || kind == EntryType.income
          ? tags
          : [],
      parts: split != null && split.length > (wholeSplit ? 0 : 1)
          ? split
          : const [],
      fee: kind == EntryType.transfer ? (takesFee ? fee : 0) : tradeFee,
      tax: kind == EntryType.dividend ? (reducing ? 0 : withheld) : tradeTax,
      refundOf: refunded?.id ?? editing?.refundOf,
      installments: onCard ? installments : 0,
      average: kind == EntryType.sell && average,
      dayTrade: kind == EntryType.sell && dayTrade,
      split: stock && splitShares && !reducing,
      home: foreign ? homeValue : null,
      received: crossing ? receivedValue : null,
      mark: kind == EntryType.expense || kind == EntryType.income ? mark : null,
    );
  }
}
