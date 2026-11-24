import '../cache/query_cache.dart';
import 'tracked_readers.dart';
import '../cache/topic.dart';
import '../models/models.dart';
import '../repositories/account_repository.dart';
import '../repositories/entry_repository.dart';
import '../repositories/market_data_repository.dart';
import '../repositories/recurring_repository.dart';

/// What falls due next for each recurring item, what it has booked and
/// the entry that would book it.
final class RecurringService {
  RecurringService({
    required EntryReader entries,
    required AccountReader accounts,
    required RecurringReader recurring,
    required MarketDataReader market,
    required this._cache,
    required this._today,
  }) : _entries = TrackedEntryReader(entries, _cache),
       _accounts = TrackedAccountReader(accounts, _cache),
       _market = TrackedMarketDataReader(market, _cache),
       _recurring = TrackedRecurringReader(recurring, _cache);

  final EntryReader _entries;
  final AccountReader _accounts;
  final RecurringReader _recurring;
  final MarketDataReader _market;
  final QueryCache _cache;
  final DateTime Function() _today;

  /// The entries booking [item] in [year]/[month], earliest first.
  List<Entry> confirmationsIn(Recurring item, int year, int month) => [
    // Exception to as-of-today: a booking written ahead, 預定, still books its
    // day.
    for (final e in _entries.inMonth(year, month).reversed)
      if (e.recurring == item.id) e,
  ];

  /// Every entry booking each recurring item, by item id, oldest day
  /// first and within a day in the order written.
  Map<String, List<Entry>> _bookings() => _cache.remember(
    'recurringBookings',
    () {
      final found = <String, List<Entry>>{};
      // Exception to as-of-today: a booking written ahead, 預定, still books its
      // day.
      for (final e in _entries.byDate) {
        final id = e.recurring;
        if (id != null) (found[id] ??= []).add(e);
      }
      return found;
    },
  );

  /// The first month whose days [item] can still be due on: that of its
  /// earliest booking, or this month when it has none, or that of a day
  /// 恢復 brought back before them ([Recurring.openFrom]). A day before it
  /// was never asked for, and is not now; every day from it on that is
  /// neither booked nor let go is, however long ago (a day 恢復 brings
  /// back included, D66).
  DateTime _firstOpenMonth(Recurring item) {
    final booked = _bookings()[item.id];
    var from = booked == null || booked.isEmpty ? _today() : booked.first.date;
    final back = item.openFrom;
    if (back != null && back.isBefore(from)) from = back;
    return DateTime.utc(from.year, from.month);
  }

  /// The day each booking of [item] settles, by the booking's id: the
  /// days it falls due (those let go left out) from its first open month
  /// to the month after the later of its latest booking and today, each
  /// taken by one booking at most. A booking dated on one of them takes
  /// it; then the rest, in order, each the earliest left in its own month,
  /// else the nearest left, none after today or the booking's own day
  /// (LOG-09: a booking moved to the day before still settles its own
  /// period). A booking with none left settles nothing.
  Map<String, DateTime> settled(Recurring item) => _cache.remember(
    ('settled', item, _today()),
    () => _settled(item),
    // The item comes in as an argument: its own changes are not read.
    reads: const {Topic.recurring},
  );

  Map<String, DateTime> _settled(Recurring item) {
    final booked = _bookings()[item.id] ?? const <Entry>[];
    if (booked.isEmpty) return const {};
    final first = _firstOpenMonth(item);
    final latest = booked.last.date.isAfter(_today())
        ? booked.last.date
        : _today();
    final open = <DateTime>{
      for (
        var m = first;
        !m.isAfter(DateTime.utc(latest.year, latest.month + 1));
        m = DateTime.utc(m.year, m.month + 1)
      )
        ...item.dueIn(m.year, m.month),
    };
    final taken = <String, DateTime>{};
    final left = <Entry>[];
    for (final e in booked) {
      if (open.remove(e.date)) {
        taken[e.id] = e.date;
      } else {
        left.add(e);
      }
    }
    for (final e in left) {
      // Never a day still to come that the booking is not dated on or
      // after: a second booking of a day does not settle next month's.
      final last = e.date.isAfter(_today()) ? e.date : _today();
      final day = nearestDay(e.date, [
        for (final d in open)
          if (!d.isAfter(last)) d,
      ]);
      if (day == null) continue;
      open.remove(day);
      taken[e.id] = day;
    }
    return taken;
  }

  /// Of [days], the one a booking dated [date] stands for: [date] itself,
  /// else the earliest in its month, else the nearest (the earlier of two
  /// as near); null when there are none.
  static DateTime? nearestDay(DateTime date, Iterable<DateTime> days) {
    DateTime? best;
    int rank(DateTime d) {
      if (d == date) return 0;
      return d.year == date.year && d.month == date.month ? 1 : 2;
    }

    for (final d in days) {
      final b = best;
      if (b == null) {
        best = d;
        continue;
      }
      final (rd, rb) = (rank(d), rank(b));
      if (rd != rb) {
        if (rd < rb) best = d;
        continue;
      }
      final gap = rd == 1
          ? d.compareTo(b)
          : d.difference(date).abs().compareTo(b.difference(date).abs());
      if (gap < 0 || (gap == 0 && d.isBefore(b))) best = d;
    }
    return best;
  }

  /// The days [item] falls due that a booking settles, each with it.
  Map<DateTime, Entry> bookedDays(Recurring item) {
    final byId = {
      for (final e in _bookings()[item.id] ?? const <Entry>[]) e.id: e,
    };
    return {
      for (final MapEntry(key: id, value: day) in settled(item).entries)
        day: byId[id]!,
    };
  }

  /// The first day [item] falls due and is not yet booked or let go,
  /// from its first open month to the end of this one: every period
  /// missed while the app was not opened, however long, and none from
  /// before what was first booked.
  DateTime? pendingDate(Recurring item) => _cache.remember(
    ('pending', item, _today()),
    () {
      if (!item.active) return null;
      final end = DateTime.utc(_today().year, _today().month + 1, 0);
      final days = unpostedDates(item, from: _firstOpenMonth(item), to: end);
      return days.isEmpty ? null : days.first;
    },
    // The item comes in as an argument: its own changes are not read.
    reads: const {Topic.recurring},
  );

  /// Every day from [from] to [to] (both counted) [item] falls due and is
  /// not booked or let go, earliest first; none for a paused item, and
  /// none before its first open month. The same days [pendingDate]
  /// counts, so what the reminders and the calendar say is still to book
  /// is what the recurring page says.
  List<DateTime> unpostedDates(
    Recurring item, {
    required DateTime from,
    required DateTime to,
  }) {
    if (!item.active) return const [];
    var month = DateTime.utc(from.year, from.month);
    final open = _firstOpenMonth(item);
    if (month.isBefore(open)) month = open;
    final booked = settled(item).values.toSet();
    final found = <DateTime>[];
    for (
      ;
      !month.isAfter(to);
      month = DateTime.utc(month.year, month.month + 1)
    ) {
      for (final d in item.dueIn(month.year, month.month)) {
        if (!d.isBefore(from) && !d.isAfter(to) && !booked.contains(d)) {
          found.add(d);
        }
      }
    }
    return found;
  }

  /// The next day [item] falls due, this month or later: however far
  /// apart its dates are (R3).
  DateTime? nextDate(Recurring item) {
    final pending = pendingDate(item);
    if (pending != null) return pending;
    if (!item.active) return null;
    final next = DateTime.utc(_today().year, _today().month + 1);
    for (final d in item.datesFrom(next, count: 2)) {
      if (!item.skipped.contains(d)) return d;
    }
    return null;
  }

  /// Active items whose day has come but are not yet booked.
  List<Recurring> get due => [
    for (final r in _recurring.all)
      if (pendingDate(r) case final d? when !d.isAfter(_today())) r,
  ];

  /// Active items still to come this month, soonest first.
  List<Recurring> get upcoming {
    final rows = [
      for (final r in _recurring.all)
        if (pendingDate(r) case final d? when d.isAfter(_today())) (r, d),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final (r, _) in rows) r];
  }

  /// The day of its recurring item [e] settles ([settled]); null for an
  /// entry booking none, or none of the days it falls due.
  DateTime? dueDayOf(Entry e) {
    final id = e.recurring;
    if (id == null) return null;
    final item = _recurring.byId(id);
    if (item == null) return null;
    return settled(item)[e.id];
  }

  /// [item]'s amount in whole NT$ at today's rate; 0 without one.
  int worth(Recurring item) =>
      _market.toHome(item.amount, _accounts.resolve(item.account).currency) ??
      0;

  /// The entry that books [item] on [day] (D66: the day 入帳 was
  /// pressed for on the calendar), else on its pending day, or today if
  /// that is later, for the composer to show before it is saved. A
  /// foreign one is worth at home what today's rate makes it only when
  /// it books today: the rates kept are today's, and no day's before
  /// (R5); a day gone by is left without, for the person to fill in, and
  /// the automatic booking leaves it to them.
  Entry booking(Recurring item, {DateTime? day}) {
    final pending = day ?? pendingDate(item) ?? _today();
    final date = pending.isAfter(_today()) ? _today() : pending;
    final currency = _accounts.resolve(item.account).currency;
    return Entry(
      id: '',
      date: date,
      type: item.income ? EntryType.income : EntryType.expense,
      amount: item.amount,
      account: item.account,
      category: item.category,
      note: item.name,
      recurring: item.id,
      merchant: item.merchant,
      home: currency == homeCode || date != _today()
          ? null
          : _market.toHome(item.amount, currency),
    );
  }
}
