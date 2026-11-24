import 'entry.dart';

/// How far ahead of today an entry may be dated: one year (D25). The one
/// limit the entry form's date picker and the write rules share.
const maxDaysAhead = 365;

/// The last day an entry may be dated on [today]: [maxDaysAhead] after
/// it. Days are UTC midnights, as entries keep them.
DateTime latestEntryDay(DateTime today) =>
    DateTime.utc(today.year, today.month, today.day + maxDaysAhead);

/// Whether what happens on [day] counts on [today]: the one "as of
/// today" predicate (D25). Balances, net worth, budgets, the overview,
/// reports and card bills count an entry only once its day has come; an
/// entry dated later is 預定 ([isPlanned]) until then, and counts at the
/// day's rollover with nothing written. Both are UTC midnights, as the
/// ledger keeps days.
bool countsOn(DateTime day, DateTime today) => !day.isAfter(today);

/// An entry dated after [today]: 預定, not counted until its day.
bool isPlanned(Entry e, DateTime today) => !countsOn(e.date, today);

/// The entries of [entries] that count on [today], in their order.
Iterable<Entry> countedOn(Iterable<Entry> entries, DateTime today) =>
    entries.where((e) => countsOn(e.date, today));
