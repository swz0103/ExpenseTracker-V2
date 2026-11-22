import 'package:ledger_trade_costs/calc/settlement.dart';
import 'package:ledger_trade_costs/model/trade_values.dart';

import 'category.dart';

/// What an entry does. Buys, sells and dividends are investment entries.
enum EntryType { expense, income, transfer, buy, sell, dividend }

/// One line of the book, in the smallest unit of its account's currency:
/// whole NT$ for most.
final class Entry {
  const Entry({
    required this.id,
    required this.date,
    required this.type,
    required this.amount,
    required this.account,
    this.category = '',
    this.note = '',
    this.to,
    this.holding,
    this.shares = 0,
    this.recurring,
    this.merchant = '',
    this.tags = const [],
    this.parts = const [],
    this.fee = 0,
    this.tax = 0,
    this.refundOf,
    this.installments = 0,
    this.average = false,
    this.split = false,
    this.home,
    this.received,
    this.group,
  });

  final String id;

  /// Midnight UTC of the day.
  final DateTime date;
  final EntryType type;
  final int amount;
  final String account;
  final String category;
  final String note;

  /// The receiving account of a transfer.
  final String? to;

  /// The stock code of an investment entry.
  final String? holding;
  final int shares;

  /// The recurring item this entry confirms.
  final String? recurring;

  /// Where the money went, such as 全聯福利中心; empty when not noted.
  final String merchant;

  /// Labels that cut across categories, such as 家用.
  final List<String> tags;

  /// A spending split across categories, each with its amount; empty when
  /// the whole goes to [category].
  final List<(String, int)> parts;

  /// The bank's fee on a transfer, the broker's on a trade.
  final int fee;

  /// What ties entries written as one together, such as a dinner paid
  /// partly for oneself and partly for friends: a spending and a transfer
  /// to each friend, with the same group. Null for an entry on its own.
  final String? group;

  /// The securities transaction tax on a sale; the NHI supplementary
  /// premium (二代健保) withheld from a dividend.
  final int tax;

  /// The spending this income gives back, for a refund.
  final String? refundOf;

  /// How many monthly instalments a card purchase is paid in; 0 for one.
  final int installments;

  /// A sale costed at the average price rather than first in, first out.
  final bool average;

  /// A dividend entry whose [shares] come from a split rather than a stock
  /// dividend: the shares held multiply at the same cost.
  final bool split;

  /// For spending or income in a foreign-currency account: what it was
  /// worth in whole NT$ that day, which the reports and budgets count.
  final int? home;

  /// For a transfer between accounts in different currencies: what
  /// reached [to], in the smallest unit of its currency.
  final int? received;

  bool get isRefund => refundOf != null;

  /// [amount] in whole NT$: [home] when the entry has one.
  int get worth => home ?? amount;

  /// What reached [to] for a transfer.
  int get arrived => received ?? amount;

  /// What the entry adds to spending: an expense, a transfer's fee; a
  /// refund takes some back.
  int get spending => switch (type) {
    EntryType.expense => worth,
    EntryType.transfer => fee,
    EntryType.income when isRefund => -worth,
    _ => 0,
  };

  /// A capital reduction: the company takes back [shares] (negative) and
  /// returns [amount] in cash, which lowers the cost rather than earning.
  bool get isReduction => type == EntryType.dividend && shares < 0;

  /// What an investment entry moves on its account, from the one rule
  /// for a trade's money (`settlementAmount`): a buy paid with its fee
  /// (negative), a sale received less fee and tax, a cash dividend less
  /// the premium withheld, the cash back of a capital reduction. 0 for
  /// any other entry.
  int get settlement {
    final kind = switch (type) {
      EntryType.buy => TradeKind.buy,
      EntryType.sell => TradeKind.sell,
      EntryType.dividend when isReduction => TradeKind.capitalReturn,
      EntryType.dividend => TradeKind.dividend,
      _ => null,
    };
    if (kind == null) return 0;
    return settlementAmount(kind, gross: amount, fee: fee, tax: tax);
  }

  /// What a dividend paid out, after the premium withheld.
  int get dividendNet =>
      type == EntryType.dividend && !isReduction ? settlement : 0;

  /// What the entry brings in: income and dividends, not refunds.
  int get earning => switch (type) {
    EntryType.income when !isRefund => worth,
    EntryType.dividend => dividendNet,
    _ => 0,
  };

  /// [spending] by category: the parts of a split, a transfer's fee under
  /// [feeCategory].
  List<(String, int)> get spendingParts {
    if (spending == 0) return const [];
    if (type == EntryType.transfer) return [(feeCategory, fee)];
    if (parts.isNotEmpty && home == null) return parts;
    return [(category, spending)];
  }

  /// This entry with the given fields changed.
  Entry _with({
    String? id,
    String? account,
    String? category,
    String? merchant,
    List<String>? tags,
    List<(String, int)>? parts,
  }) => Entry(
    id: id ?? this.id,
    date: date,
    type: type,
    amount: amount,
    account: account ?? this.account,
    category: category ?? this.category,
    note: note,
    to: to,
    holding: holding,
    shares: shares,
    recurring: recurring,
    merchant: merchant ?? this.merchant,
    tags: tags ?? this.tags,
    parts: parts ?? this.parts,
    fee: fee,
    tax: tax,
    refundOf: refundOf,
    installments: installments,
    average: average,
    split: split,
    home: home,
    received: received,
    group: group,
  );

  /// This entry as one of those written together as [group] (none when
  /// null), under [id] and for [amount] when given.
  Entry inGroup(String? group, {String? id, int? amount}) => Entry(
    id: id ?? this.id,
    date: date,
    type: type,
    amount: amount ?? this.amount,
    account: account,
    category: category,
    note: note,
    to: to,
    holding: holding,
    shares: shares,
    recurring: recurring,
    merchant: merchant,
    tags: tags,
    parts: parts,
    fee: fee,
    tax: tax,
    refundOf: refundOf,
    installments: installments,
    average: average,
    split: split,
    home: home,
    received: received,
    group: group,
  );

  /// This entry under another [id], as the store knows it after an edit.
  Entry withId(String id) => _with(id: id);

  /// This entry kept in [account] instead.
  Entry withAccount(String account) => _with(account: account);

  /// This entry with its merchant or tags changed.
  Entry withLabels({String? merchant, List<String>? tags}) =>
      _with(merchant: merchant, tags: tags);

  /// This entry with [from], or its category, renamed to [name].
  Entry withCategory(String name, {String? from}) {
    // Parts that end up in the same category become one.
    final merged = <String, int>{};
    for (final (part, value) in parts) {
      final into = part == (from ?? category) ? name : part;
      merged[into] = (merged[into] ?? 0) + value;
    }
    final renamed = from == null || category == from ? name : category;
    return _with(
      category: merged.length == 1 ? merged.keys.single : renamed,
      parts: merged.length < 2
          ? const []
          : [for (final MapEntry(:key, :value) in merged.entries) (key, value)],
    );
  }

  /// What the lists show: the note, else the category.
  String get title => note.isNotEmpty ? note : category;

  bool get isInvestment =>
      type == EntryType.buy ||
      type == EntryType.sell ||
      type == EntryType.dividend;
}
