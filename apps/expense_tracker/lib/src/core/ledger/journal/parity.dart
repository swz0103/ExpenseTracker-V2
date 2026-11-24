import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:kernel/kernel.dart';
import 'package:ledger_postings/calc/statement.dart';
import 'package:ledger_postings/model/vocabulary.dart';

import '../card_cycle.dart';
import '../models/models.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/holding_repository.dart';
import '../services/balance_service.dart';
import '../services/report_service.dart';
import '../services/statement_service.dart';
import 'old_shapes.dart';

/// What the app shows today, as its own services work it out: the side
/// of the comparison the journal must match.
typedef TodaysFigures = ({
  /// Today, as the app counts it: an entry dated later is 預定 (D25),
  /// in none of the figures until its day.
  DateTime day,
  EntryReader entries,
  AccountReader accounts,
  HoldingReader holdings,
  BalanceService balances,
  ReportService reports,
  StatementService statements,
});

/// A figure the app shows that the journal must give the same.
enum Figure {
  /// An account's balance at the end of a day.
  balance,

  /// A month's income, dividends included.
  income,

  /// A month's spending, less refunds, with transfer fees.
  spending,

  /// A month's spending under one category.
  categorySpending,

  /// A stock's shares, what they cost, its gain and its dividends.
  shares,
  cost,
  realised,
  dividends,

  /// What is still to pay on a card's last statement.
  statementDue,

  /// What one currency's postings come to: zero in a sound book.
  trialBalance,

  /// A record the journal would not post at all.
  unposted,
}

/// One figure that differs: what, of which account, month, stock or
/// record (`subject`), when (`at`), and the two amounts.
typedef Difference = ({
  Figure figure,
  String subject,
  String at,
  int app,
  int postings,
});

/// What comparing a book's figures with its postings found.
sealed class Parity {
  const Parity({required this.figures, required this.shapes});

  /// How many figures were compared.
  final int figures;

  /// The old shapes the book has, by how many records.
  final Map<OldShape, int> shapes;
}

/// Every figure compared is the same.
final class InParity extends Parity {
  const InParity({required super.figures, required super.shapes});
}

/// Some figures differ.
final class OutOfParity extends Parity {
  const OutOfParity({
    required super.figures,
    required super.shapes,
    required this.differences,
  });

  final List<Difference> differences;

  /// The differences in words for the diagnostics log: which figures of
  /// what, never an amount.
  String get described =>
      [for (final d in differences) '${d.figure.name} ${d.subject} ${d.at}']
          .join('; ');
}

/// What of a book to compare: every account, month and stock, or those a
/// write touched (null: all of that kind).
typedef ParityScope = ({
  Set<String>? accounts,
  Set<int>? months,
  Set<String>? codes,
});

const ParityScope everything = (accounts: null, months: null, codes: null);

/// Compares what [today] shows with what [reader] sums from the
/// postings, within [scope]: each account's balance at the end of each
/// day either side changes it, each month's income, spending and
/// spending by category, each stock's shares, cost, gain and dividends,
/// each card's statement due, and that every currency comes to zero.
/// [unposted] are records the journal refused; [shapes] the old shapes
/// met. [pause] runs between accounts, so a large book's check does not
/// hold the screen still. With [everyDay], balances are compared at the
/// end of every day from the day before the first change to the day
/// after the last, not only on the days they change.
Future<Parity> checkParity({
  required TodaysFigures today,
  required BookReader reader,
  ParityScope scope = everything,
  bool everyDay = false,
  Map<OldShape, int> shapes = const {},
  List<JournalRefusal> unposted = const [],
  Future<void> Function()? pause,
}) async {
  final differences = <Difference>[];
  var figures = 0;
  void check(Figure figure, String subject, String at, int app, int posted) {
    figures++;
    if (app != posted) {
      differences.add((
        figure: figure,
        subject: subject,
        at: at,
        app: app,
        postings: posted,
      ));
    }
  }

  bool inScope(Set<String>? within, String id) =>
      within == null || within.contains(id);

  // As of today (D25): a 預定 entry's postings are dated at its day. The
  // app counts it in a balance at that day or later, as the postings do,
  // but in no month's report or holding until the day comes: those are
  // read up to today.
  final now = Day.of(BusinessDate.of(today.day));

  // 1. Balances, at the end of each day either side changes them.
  final days = _changeDays(today);
  for (final a in today.accounts.all) {
    if (!inScope(scope.accounts, a.id)) continue;
    final postings = reader.postings(moneyAccount(a.id));
    final running = <int, int>{};
    var total = 0;
    for (final p in postings) {
      total += p.amount;
      running[p.date.ymd] = total;
    }
    final changes = {...?days[a.id], for (final p in postings) p.date.ymd};
    final when = (everyDay ? _everyDay(changes) : changes.toList())..sort();
    var kept = 0;
    var k = 0;
    final sortedDays = running.keys.toList()..sort();
    for (final ymd in when) {
      while (k < sortedDays.length && sortedDays[k] <= ymd) {
        kept = running[sortedDays[k++]]!;
      }
      final day = Day.stored(ymd);
      check(
        Figure.balance,
        a.id,
        '${day.date}',
        today.balances.balanceThrough(a.id, day.date.asUtcMidnight),
        kept,
      );
    }
    if (pause != null) await pause();
  }

  // 2. Each month's income, spending and spending by category.
  for (final month in _months(today.entries)) {
    if (scope.months != null && !scope.months!.contains(month)) continue;
    final first = Day.stored(month * 100 + 1);
    final last = first.lastOfMonth;
    // Up to today: what a month after it holds is 預定 (an entry's
    // income and spending are posted at its own day).
    final report = reader.period(first, last.ymd > now.ymd ? now : last);
    final label = '${first.year}-${first.month}';
    check(
      Figure.income,
      'book',
      label,
      today.reports.income(first.year, first.month),
      report.incomeTotal,
    );
    check(
      Figure.spending,
      'book',
      label,
      today.reports.expense(first.year, first.month),
      report.spendingTotal,
    );
    final app = today.reports.spendingBetween(
      first.date.asUtcMidnight,
      last.date.asUtcMidnight,
    )..removeWhere((_, v) => v == 0);
    final posted = <String, int>{};
    for (final MapEntry(key: id, value: amount) in report.spending.entries) {
      final name = reader.accounts[id]!.name;
      posted[name] = (posted[name] ?? 0) + amount;
    }
    posted.removeWhere((_, v) => v == 0);
    for (final name in {...app.keys, ...posted.keys}) {
      check(
        Figure.categorySpending,
        name,
        label,
        app[name] ?? 0,
        posted[name] ?? 0,
      );
    }
  }

  // 3. Each stock: what the holdings list, and any the postings hold.
  int bySub(AccountId account, String code) => -reader
      .bySub(account, until: now)
      .where((l) => l.sub == code)
      .fold(0, (sum, l) => sum + l.amount);
  final listed = {for (final h in today.holdings.all) h.code: h};
  final held = {
    ...listed.keys,
    for (final a in reader.accounts.where(tag: Tags.holding)) a.commodity!,
  };
  for (final code in held) {
    if (!inScope(scope.codes, code)) continue;
    final account = holdingAccount(code);
    final shares = wholeUnits(reader.quantity(account, until: now));
    final h = listed[code];
    check(Figure.shares, code, 'now', h?.shares ?? 0, shares);
    if (h == null) continue; // sold out with nothing gained: not listed
    check(
      Figure.cost,
      code,
      'now',
      h.cost,
      reader.balance(account, until: now),
    );
    check(
      Figure.realised,
      code,
      'now',
      h.realized,
      bySub(Fixed.realisedGains, code),
    );
    check(
      Figure.dividends,
      code,
      'now',
      h.dividends,
      bySub(Fixed.dividends, code),
    );
  }

  // 4. Each card's last statement.
  for (final a in today.accounts.all) {
    if (a.kind != AccountKind.card || !inScope(scope.accounts, a.id)) continue;
    final (_, closed, _) = today.statements.statement(a);
    check(
      Figure.statementDue,
      a.id,
      '${BusinessDate.of(closed)}',
      today.statements.statementDue(a),
      statementDue(moneyAccount(a.id), Day.of(BusinessDate.of(closed)), reader),
    );
  }

  // 5. Every currency comes to zero.
  for (final MapEntry(key: currency, value: sum)
      in reader.trialBalance().entries) {
    check(Figure.trialBalance, currency.value, 'all', 0, sum);
  }
  for (final refused in unposted) {
    check(Figure.unposted, refused.intent.value, _why(refused), 1, 0);
  }

  return differences.isEmpty
      ? InParity(figures: figures, shapes: shapes)
      : OutOfParity(figures: figures, shapes: shapes, differences: differences);
}

/// The days each account changes on today, by account: the day of each
/// entry paid from or into it, and each day an instalment is billed.
Map<String, Set<int>> _changeDays(TodaysFigures today) {
  final days = <String, Set<int>>{};
  void add(String account, DateTime day) =>
      (days[account] ??= {}).add(Day.of(BusinessDate.of(day)).ymd);
  for (final e in today.entries.all) {
    if (e.type == EntryType.expense && e.installments > 1) {
      for (final (day, _)
          in today.accounts.resolve(e.account).billingSteps(e)) {
        add(e.account, day);
      }
    } else {
      add(e.account, e.date);
    }
    if (e.to case final to?) add(to, e.date);
  }
  return days;
}

/// [changes] and every day from the day before the first of them to the
/// day after the last; the day before every record stays as it is.
List<int> _everyDay(Set<int> changes) {
  final dated = changes.where((d) => d != Day.beforeAll.ymd).toList()..sort();
  if (dated.isEmpty) return changes.toList();
  final last = Day.stored(dated.last).date.addDays(1);
  return [
    ...changes.where((d) => d == Day.beforeAll.ymd),
    for (
      var d = Day.stored(dated.first).date.addDays(-1);
      !d.isAfter(last);
      d = d.addDays(1)
    )
      Day.of(d).ymd,
  ];
}

/// Every month from the first entry's to the last's, as year × 100 +
/// month.
List<int> _months(EntryReader reader) {
  final entries = reader.all;
  if (entries.isEmpty) return const [];
  var first = entries.first.date;
  var last = first;
  for (final e in entries) {
    if (e.date.isBefore(first)) first = e.date;
    if (e.date.isAfter(last)) last = e.date;
  }
  return [
    for (
      var m = DateTime.utc(first.year, first.month);
      !m.isAfter(last);
      m = DateTime.utc(m.year, m.month + 1)
    )
      m.year * 100 + m.month,
  ];
}

/// Why the journal refused a record, in its own word.
String _why(JournalRefusal refused) => switch (refused) {
  Unbalanced() => 'unbalanced',
  UnknownAccount() => 'unknownAccount',
  CurrencyMismatch() => 'currencyMismatch',
  UnknownIntentType() => 'unknownIntentType',
  IntentNotFound() => 'intentNotFound',
  RuleRejected(:final code) => code,
  UnknownAmendment() => 'unknownAmendment',
};
