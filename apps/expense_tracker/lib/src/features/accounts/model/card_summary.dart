import 'package:core/foundation_values.dart'
    show BusinessDate, BusinessDayAnswer;
import 'package:core/percent/percent.dart' show percent;
import 'package:domain/credit_cards.dart' show CardBillStatus;

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

  /// Where the last statement stands today: paid, due or overdue.
  late final CardBillStatus billStatus = _statements.billStatus(card);

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

  /// What is left to be billed of [e] after today, as [debt] is read at
  /// the end of today: an instalment billed today is owed, not still to
  /// bill, so the credit taken is counted once on a closing day (D67);
  /// what refunds cancelled is billed.
  int unbilledOf(Entry e) => _balances.stillToBill(e);

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

  /// What entries on the card marked [mark] (D52: by their mark, never a
  /// tag's words) came to this year, of those that count [today]
  /// ([countsOn]): a 預定 one joins on its day. A refund of one (an
  /// annual fee waived) takes back what it gives back (r13 F7).
  int markedThisYear(EntryMark mark) {
    final year = today.year;
    var total = 0;
    for (var month = 1; month <= today.month; month++) {
      for (final e in countedOn(_entries.inMonth(year, month), today)) {
        total += _markedPart(e, mark);
      }
    }
    return total;
  }

  /// What [e] adds to the card's total of [mark]: its amount when marked
  /// so, less it for a refund of one so marked, else nothing.
  int _markedPart(Entry e, EntryMark mark) {
    if (e.account != card.id) return 0;
    if (e.mark == mark) return e.amount;
    final of = e.refundOf;
    if (of != null && _entries.byId(of)?.mark == mark) return -e.amount;
    return 0;
  }

  /// What entries on the card marked [mark] came to since the last
  /// close: the cycle not billed yet, of those that count [today].
  int markedSinceClose(EntryMark mark) {
    var total = 0;
    for (final e in countedOn(_entries.all, today)) {
      if (e.date.isAfter(end)) total += _markedPart(e, mark);
    }
    return total;
  }

  /// The transfer that pays the statement from the main account; null
  /// when nothing is owed.
  Entry? get payment => owed == 0
      ? null
      : TransferDrafts(
          main: _accounts.main,
          today: today,
        ).payInto(card.id, amount: owed, note: '${card.name}繳款');

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
      mark: reward ? EntryMark.reward : EntryMark.annualFee,
    );
  }
}
