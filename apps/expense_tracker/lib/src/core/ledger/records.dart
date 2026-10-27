import 'dart:math';

import 'package:domain/credit_cards.dart' show CardScheduleChange;
import 'package:domain/investments.dart' show unitsPerShare;
import 'package:flutter/painting.dart' show Color;

/// The code of the currency the books are kept in: NT$.
const homeCode = 'TWD';

/// The category every transfer carries.
const transferCategory = '轉帳';

/// Where fees go that have no category of their own, such as a
/// transfer's.
const feeCategory = '其他支出';

/// What an entry does. Buys, sells and dividends are investment entries.
enum EntryType { expense, income, transfer, buy, sell, dividend }

enum AccountKind {
  cash,
  bank,
  wallet,
  card,
  loan,
  receivable;

  /// Kinds whose balance is owed rather than held.
  bool get isDebt => this == card || this == loan;
}

final class Account {
  const Account(
    this.id,
    this.name,
    this.kind,
    this.opening, {
    this.icon,
    this.closingDay,
    this.dueDay,
    this.limit,
    this.archived = false,
    this.inNetWorth = true,
    this.currency = homeCode,
    this.closes = const {},
    this.history = const [],
  });

  final String id;
  final String name;
  final AccountKind kind;

  /// What the account is kept in, such as TWD or USD. Its [opening], its
  /// entries and its balance count the smallest unit of it: whole NT$,
  /// US cents.
  final String currency;

  /// Kept in a currency other than NT$.
  bool get foreign => currency != homeCode;

  /// A card's statements that close on another day than scheduled, such
  /// as around a holiday: the actual close by the scheduled one.
  final Map<DateTime, DateTime> closes;

  /// A card's earlier billing days, oldest first, so statements closed
  /// before a change keep their dates.
  final List<CardScheduleChange> history;

  /// The account's own mark, such as 'safe' or 'chat'; null takes the
  /// mark of its [kind].
  final String? icon;

  /// The balance before the first entry; negative for card debt.
  final int opening;

  /// A card's statement closing day and payment day of the month, and
  /// its credit limit.
  final int? closingDay;
  final int? dueDay;
  final int? limit;

  /// Closed and kept only for its history: left out of lists and pickers.
  final bool archived;

  /// Counted in the totals and net worth.
  final bool inNetWorth;

  Account copyWith({
    String? name,
    AccountKind? kind,
    int? opening,
    String? icon,
    int? closingDay,
    int? dueDay,
    int? limit,
    bool? archived,
    bool? inNetWorth,
    Map<DateTime, DateTime>? closes,
    List<CardScheduleChange>? history,
  }) => Account(
    id,
    name ?? this.name,
    kind ?? this.kind,
    opening ?? this.opening,
    icon: icon ?? this.icon,
    closingDay: closingDay ?? this.closingDay,
    dueDay: dueDay ?? this.dueDay,
    limit: limit ?? this.limit,
    archived: archived ?? this.archived,
    inNetWorth: inNetWorth ?? this.inNetWorth,
    currency: currency,
    closes: closes ?? this.closes,
    history: history ?? this.history,
  );
}

final class Category {
  const Category(
    this.name,
    this.icon,
    this.color, {
    this.income = false,
    this.parent,
    this.archived = false,
  });

  final String name;

  /// A key into the app's icon set, such as `food`.
  final String icon;
  final Color color;
  final bool income;

  /// The category this one sits under, if any.
  final String? parent;

  /// No longer offered for new entries; its history stays.
  final bool archived;

  Category copyWith({
    String? name,
    String? parent,
    bool clearParent = false,
    bool? archived,
  }) => Category(
    name ?? this.name,
    icon,
    color,
    income: income,
    parent: clearParent ? null : parent ?? this.parent,
    archived: archived ?? this.archived,
  );
}

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

  /// What a dividend paid out, after the premium withheld.
  int get dividendNet =>
      type == EntryType.dividend && !isReduction ? amount - tax : 0;

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

final class Holding {
  const Holding(
    this.code,
    this.name, {
    required this.shares,
    required this.price,
    required this.cost,
    required this.change,
    this.dividends = 0,
    this.realized = 0,
  });

  final String code;
  final String name;
  final int shares;

  /// The reference close, in NT$ with decimals.
  final double price;

  /// What the shares still held cost.
  final int cost;

  /// Today's change in market value.
  final int change;

  /// Dividends received so far.
  final int dividends;

  /// Profit or loss of shares already sold.
  final int realized;

  int get value => (shares * price).round();

  int get gain => value - cost;

  /// This holding with [change] as the day's change in value.
  Holding withChange(int change) => Holding(
    code,
    name,
    shares: shares,
    price: price,
    cost: cost,
    change: change,
    dividends: dividends,
    realized: realized,
  );

  Holding copyWith({
    int? shares,
    double? price,
    int? cost,
    int? dividends,
    int? realized,
  }) => Holding(
    code,
    name,
    shares: shares ?? this.shares,
    price: price ?? this.price,
    cost: cost ?? this.cost,
    change: change,
    dividends: dividends ?? this.dividends,
    realized: realized ?? this.realized,
  );
}

/// Shares bought together and still held, with what they cost.
final class Lot {
  /// A lot of whole [shares].
  Lot(this.date, int shares, this.cost)
    : units = BigInt.from(shares) * unitsPerShare;

  /// A lot of exact [units], 10^-12 of a share each, as a split or a
  /// stock dividend can leave it.
  const Lot.units(this.date, this.units, this.cost);

  /// The date a starting position is held from: before any entry, so the
  /// first trade of a stock always comes after it.
  static final opening = DateTime.utc(1970);

  final DateTime date;
  final BigInt units;
  final int cost;

  /// Whole shares, rounded.
  int get shares => _divideRounded(units, unitsPerShare).toInt();

  /// Whether this lot is part of a starting position.
  bool get isOpening => date == opening;
}

BigInt _divideRounded(BigInt numerator, BigInt denominator) {
  final quotient = numerator ~/ denominator;
  return numerator.remainder(denominator) * BigInt.two >= denominator
      ? quotient + BigInt.one
      : quotient;
}

final class Budget {
  const Budget(
    this.category,
    this.limit, {
    this.warning = 80,
    this.carry = false,
    this.since,
  });

  /// A category name, [Ledger.allSpending] for the total, or `#` and a
  /// tag for the spending carrying it, such as `#旅遊`.
  final String category;
  final int limit;

  /// The tag of a tag budget; null for a category or the total.
  String? get tag => category.startsWith('#') ? category.substring(1) : null;

  /// The share used, in percent, at which the budget warns.
  final int warning;

  /// Whether what was left of last month's limit is added to this month's.
  final bool carry;

  /// The first day of the first month the budget counts; null when not
  /// known.
  final DateTime? since;

  /// This budget under the name [category], as when it is renamed.
  Budget renamed(String category) =>
      Budget(category, limit, warning: warning, carry: carry, since: since);
}

/// How often a recurring item comes round.
enum RepeatUnit {
  day('天'),
  week('週'),
  month('個月'),
  year('年');

  const RepeatUnit(this.label);

  final String label;
}

final class Recurring {
  const Recurring({
    required this.id,
    required this.name,
    required this.amount,
    required this.day,
    required this.account,
    required this.category,
    this.active = true,
    this.unit = RepeatUnit.month,
    this.every = 1,
    this.start,
    this.end,
    this.income = false,
    this.merchant = '',
    this.auto = false,
  });

  final String id;
  final String name;
  final int amount;

  /// Booked by itself on its day, when the ledger is next opened, rather
  /// than confirmed each time.
  final bool auto;

  /// Day of the month it falls due, for monthly items without [start].
  final int day;
  final String account;
  final String category;
  final bool active;
  final RepeatUnit unit;

  /// Every how many [unit]s.
  final int every;

  /// The first time it falls due; the weekday, day or date it keeps.
  final DateTime? start;

  /// The last day it may fall due, if it ends.
  final DateTime? end;

  /// Money coming in, such as a salary, rather than going out.
  final bool income;
  final String merchant;

  /// 「每月 5 日」「每 2 週 週五」「每年 3/15」.
  String get rhythm {
    final first = start;
    final n = every == 1 ? '' : ' $every ';
    final weekday = first == null ? '' : ' 週${_weekdays[first.weekday - 1]}';
    final date = first == null ? '' : ' ${first.month}/${first.day}';
    return switch (unit) {
      RepeatUnit.day => '每$n天',
      RepeatUnit.week => '每$n週$weekday',
      RepeatUnit.month =>
        '每$n${every == 1 ? '月' : '個月'} ${first?.day ?? day} 日',
      RepeatUnit.year => '每$n年$date',
    };
  }

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  Recurring copyWith({
    String? name,
    int? amount,
    String? account,
    String? category,
    bool? active,
    bool? auto,
  }) => Recurring(
    id: id,
    name: name ?? this.name,
    amount: amount ?? this.amount,
    day: day,
    account: account ?? this.account,
    category: category ?? this.category,
    active: active ?? this.active,
    unit: unit,
    every: every,
    start: start,
    end: end,
    income: income,
    merchant: merchant,
    auto: auto ?? this.auto,
  );

  /// The days in [year]/[month] it falls due.
  List<DateTime> datesIn(int year, int month) {
    final last = DateTime.utc(year, month + 1, 0);
    final first = start ?? DateTime.utc(2025, 1, day);
    final stop = end;
    bool keep(DateTime d) =>
        !d.isBefore(first) && (stop == null || !d.isAfter(stop));
    final dates = <DateTime>[];
    switch (unit) {
      case RepeatUnit.day || RepeatUnit.week:
        final step = every * (unit == RepeatUnit.week ? 7 : 1);
        final monthStart = DateTime.utc(year, month);
        final gap = monthStart.difference(first).inDays;
        var d = gap <= 0
            ? first
            : first.add(Duration(days: (gap + step - 1) ~/ step * step));
        while (!d.isAfter(last)) {
          if (keep(d)) dates.add(d);
          d = d.add(Duration(days: step));
        }
      case RepeatUnit.month:
        final months = (year - first.year) * 12 + month - first.month;
        if (months >= 0 && months % every == 0) {
          final d = DateTime.utc(year, month, min(first.day, last.day));
          if (keep(d)) dates.add(d);
        }
      case RepeatUnit.year:
        final years = year - first.year;
        if (month == first.month && years >= 0 && years % every == 0) {
          final d = DateTime.utc(year, month, min(first.day, last.day));
          if (keep(d)) dates.add(d);
        }
    }
    return dates;
  }
}

/// An entry deleted on [on], kept for a while to be restored.
final class Trashed {
  const Trashed(this.entry, this.on);

  final Entry entry;
  final DateTime on;
}
