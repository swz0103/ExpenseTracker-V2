import 'package:domain/credit_cards.dart';
import 'package:kernel/kernel.dart';

import '../calc/conversion.dart';
import '../model/intents.dart';
import '../model/vocabulary.dart';

// The two amenders: owners that rewrite the lines of another owner's
// intent, driven by a value kept with it. A spending stays a spending
// whatever its account; a foreign value and instalments amend it.

/// Restates every line not in its account's currency (or a category's
/// line not in the book's) by the [ForeignValue] kept under [Slots.fx],
/// the far side on the currency trading account; refuses such lines
/// without one, and a value with nothing to restate.
final fxAmender = Amender(
  slot: Slots.fx,
  owner: Owners.fx,
  order: 20,
  amend: (a) => switch (a.value) {
    final ForeignValue? value => restate(
      a.lines,
      accounts: a.context.accounts,
      home: homeCurrency,
      value: value,
      trading: Fixed.currencyTrading,
      slot: Slots.fx,
    ),
    _ => Refused('fx.badValue', Slots.fx),
  },
);

/// When each instalment of a purchase on [account] is billed, by the
/// account's own schedule: data the posting rules read, not a setting.
/// Null for an account with none.
typedef ScheduleOf = CardSchedule? Function(AccountId account);

/// Spreads the one undated credit on a money account over the statements
/// that bill it, by the number of instalments kept under
/// [Slots.instalments]: the spending is whole on its day, what the
/// account owes grows statement by statement, the rest waiting on the
/// account's pending instalments.
Amender instalmentsAmender(ScheduleOf scheduleOf) => Amender(
  slot: Slots.instalments,
  owner: Owners.cards,
  order: 10,
  amend: (a) => _instalments(a, scheduleOf),
  streams: (touched, value, accounts) => [
    if (value != null)
      for (final account in touched)
        if (accounts[account]?.currency != null) Streams.instalments(account),
  ],
);

Posted _instalments(Amendment a, ScheduleOf scheduleOf) {
  final value = a.value;
  if (value == null) return Lines(a.lines);
  if (value is! int || value < 2) {
    return const Refused('instalments.count', Slots.instalments);
  }
  final credits = [
    for (final (i, line) in a.lines.indexed)
      if (line.date == null &&
          line.amount < 0 &&
          (a.context.accounts[line.account]?.cls.isBalanceSheet ?? false))
        i,
  ];
  if (credits.length != 1) {
    return const Refused('instalments.notOneAccount', Slots.instalments);
  }
  final at = credits.single;
  final line = a.lines[at];
  final schedule = scheduleOf(line.account);
  if (schedule == null) {
    return const Refused('instalments.noSchedule', Slots.instalments);
  }
  final pending = pendingInstalments(line.account);
  final amount = -line.amount;
  final shares = installmentShares(amount, value);
  final days = installmentBillingDays(schedule, a.intent.date.date, value);
  return Lines([
    for (final (i, l) in a.lines.indexed)
      if (i != at) l,
    Line(pending, -amount, line.currency),
    for (final (k, day) in days.indexed) ...[
      Line(pending, shares[k], line.currency, date: Day.of(day)),
      Line(line.account, -shares[k], line.currency, date: Day.of(day)),
    ],
  ]);
}
