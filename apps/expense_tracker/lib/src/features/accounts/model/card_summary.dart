import 'package:core/foundation_values.dart'
    show BusinessDate, BusinessDayAnswer, taiwanHolidays;
import 'package:core/percent/percent.dart' show percent;

import '../../../core/ledger/ledger.dart';

/// What a card's page shows, worked out from the book: the last statement
/// and what is still owed on it, what has been spent since, the credit
/// left, the purchases paid in instalments, cashback and fees this year,
/// and the entries its buttons start. The words are the page's; every sum
/// and every day is here, so it can be checked without a screen.
final class CardSummary {
  /// [card] as the book holds it [today].
  CardSummary.of(
    this.card, {
    required this._statements,
    required this._balances,
    required this._entries,
    required this._accounts,
    required this.today,
  });

  final StatementService _statements;
  final BalanceService _balances;
  final EntryReader _entries;
  final AccountReader _accounts;
  final Account card;
  final DateTime today;

  /// The last statement closed: its first and last day, and when it must
  /// be paid.
  late final (DateTime, DateTime, DateTime) statement = _statements.statement(
    card,
  );
  DateTime get start => statement.$1;
  DateTime get end => statement.$2;
  DateTime get due => statement.$3;

  /// What is still to pay on the last statement.
  late final int owed = _statements.statementDue(card);

  /// Purchases since the statement closed, and refunds against them.
  late final List<Entry> unbilled = _statements.unbilled(card);

  /// What [unbilled] comes to.
  late final int spentSince = unbilled.fold(
    0,
    (sum, e) => sum - _balances.effect(e, card.id),
  );

  /// Purchases still being paid in instalments.
  late final List<Entry> plans = _statements.instalmentsOn(card);

  /// How many instalments of [e] have been billed.
  int periodsBilled(Entry e) =>
      _statements.billedPeriods(e, _statements.closedBy);

  /// What 第 n 期 of [e] comes to, n being [periodsBilled] (the first
  /// before any is billed): the first period carries what does not divide
  /// evenly.
  int periodAmount(Entry e) {
    final amounts = installmentAmounts(e.amount, e.installments);
    return amounts[(periodsBilled(e) - 1).clamp(0, amounts.length - 1)];
  }

  /// What is left to be billed of [e].
  int unbilledOf(Entry e) =>
      e.amount - _statements.billed(e, _statements.closedBy);

  /// What the instalment purchases have left to bill, all together.
  late final int pending = plans.fold(0, (sum, e) => sum + unbilledOf(e));

  /// What is owed on the card now, as a positive amount.
  late final int debt = -_balances.balance(card.id);

  int? get limit => card.limit;

  /// The credit left: the limit less what is owed and what instalments
  /// will still bill; null without a limit.
  int? get available {
    final l = limit;
    return l == null ? null : l - debt - pending;
  }

  /// How much of the limit is taken, from 0 to 1; null without a limit.
  double? get usedShare {
    final l = limit;
    if (l == null || l <= 0) return null;
    return ((debt + pending) / l).clamp(0, 1).toDouble();
  }

  /// The share taken, as a whole percent; null without a limit.
  int? get usedPercent {
    final l = limit;
    if (l == null || l <= 0) return null;
    return percent(debt + pending, l);
  }

  /// Whether 80% or more of the limit is taken.
  bool get nearLimit {
    final l = limit;
    return l != null && l > 0 && (debt + pending) * 100 >= l * 80;
  }

  /// The close after the last one, which ends the cycle under way.
  late final DateTime following = card.closingOn(
    DateTime.utc(end.year, end.month + 1, end.day),
  );

  /// The days of the cycle under way, and how many have gone.
  int get cycleDays => following.difference(end).inDays;
  int get daysGone => today.difference(end).inDays;

  /// When the statement can still be paid: [due], or the next business
  /// day when it falls on a weekend or a holiday. The stored due day is
  /// left as it is.
  BusinessDayAnswer<BusinessDate> get payBy => payByOf(due);

  /// Days left to pay the statement, to [payBy]; below zero when overdue.
  int get daysLeft => payBy.value.asUtcMidnight.difference(today).inDays;

  /// The next close, as it may have been moved.
  late final DateTime nextClose = card.closingOn(
    end.add(const Duration(days: 40)),
  );

  /// The day [nextClose] was due before it was moved, if it was.
  DateTime get scheduledClose {
    for (final MapEntry(:key, :value) in card.closes.entries) {
      if (value == nextClose) return key;
    }
    return nextClose;
  }

  /// The billing days, as set or as the ledger takes them unset.
  int get closingDay => card.closingDay ?? 1;
  int get dueDay => card.dueDay ?? 15;

  /// What entries on the card of [type] tagged [tag] came to this year.
  int taggedThisYear(String tag, EntryType type) {
    final year = today.year;
    var total = 0;
    for (var month = 1; month <= today.month; month++) {
      for (final e in _entries.inMonth(year, month)) {
        if (e.account == card.id && e.type == type && e.tags.contains(tag)) {
          total += e.amount;
        }
      }
    }
    return total;
  }

  /// What entries on the card of [type] tagged [tag] came to since the
  /// last close: the cycle not billed yet.
  int taggedSinceClose(String tag, EntryType type) {
    var total = 0;
    for (final e in _entries.all) {
      if (e.account == card.id &&
          e.type == type &&
          e.tags.contains(tag) &&
          e.date.isAfter(end)) {
        total += e.amount;
      }
    }
    return total;
  }

  /// The transfer that pays the statement from the main account; null
  /// when nothing is owed.
  Entry? get payment => owed == 0
      ? null
      : Entry(
          id: '',
          date: today,
          type: EntryType.transfer,
          amount: owed,
          account: _accounts.main,
          category: transferCategory,
          note: '${card.name}繳款',
          to: card.id,
        );

  /// A spending on the card, to fill in.
  Entry get spending => Entry(
    id: '',
    date: today,
    type: EntryType.expense,
    amount: 0,
    account: card.id,
  );

  /// A cashback credit ([EntryType.income]) or an annual fee
  /// ([EntryType.expense]) on the card, to fill in.
  Entry extra(EntryType type) {
    final reward = type == EntryType.income;
    return Entry(
      id: '',
      date: today,
      type: type,
      amount: 0,
      account: card.id,
      category: reward ? '其他收入' : feeCategory,
      note: '${card.name}${reward ? '回饋' : '年費'}',
      tags: [reward ? '回饋' : '年費'],
    );
  }
}

/// When a statement due on [due] can be paid by: [due], or the next
/// business day on Taiwan's calendar when it falls on a day off (banks
/// take payment then without a late fee).
BusinessDayAnswer<BusinessDate> payByOf(DateTime due) =>
    taiwanHolidays.onOrAfter(BusinessDate.of(due));
