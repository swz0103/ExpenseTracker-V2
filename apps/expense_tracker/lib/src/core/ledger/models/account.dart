import 'package:domain/credit_cards.dart' show CardScheduleChange;
import 'package:domain/loans.dart' show LoanRepay;

export 'package:domain/loans.dart' show LoanRepay;

/// The code of the currency the books are kept in: NT$.
const homeCode = 'TWD';

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
    this.principal,
    this.place,
    this.color,
    this.loan,
  });

  final String id;

  /// The colour picked for the account, as ARGB; null takes its [kind]'s.
  final int? color;

  /// A loan's terms; null for any other account, or a loan without them.
  final LoanTerms? loan;
  final String name;
  final AccountKind kind;

  /// A loan's amount when it was taken out, so what is paid of it shows;
  /// null when not given.
  final int? principal;

  /// Where the account stands on 我的帳戶, in the order set there; null
  /// for one never placed, which follows the placed ones by kind.
  final int? place;

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
    int? principal,
    int? place,
    int? color,
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
    principal: principal ?? this.principal,
    place: place ?? this.place,
    color: color ?? this.color,
    loan: loan,
  );
}

/// What a loan costs and how it is paid: its yearly interest in
/// hundredths of a percent (215 is 2.15%), how many months it runs, how
/// it is paid back and the account it is paid from; each null when not
/// given.
final class LoanTerms {
  const LoanTerms({this.rate, this.months, this.repay, this.payFrom});

  final int? rate;
  final int? months;
  final LoanRepay? repay;
  final String? payFrom;

  /// Whether nothing is given, so the account keeps no terms.
  bool get isEmpty =>
      rate == null && months == null && repay == null && payFrom == null;
}
