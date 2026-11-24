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

  /// The first day [item] falls due and is not yet booked or let go, from
  /// the month of its latest booking on (this month's, before its first):
  /// every period missed while the app was not opened, however long, and
  /// none from before what was last booked. Bookings count against a
  /// month's days in order, so one booked early still settles that day.
  DateTime? pendingDate(Recurring item) => _cache.remember(
    ('pending', item.id, item.active, _today()),
    () => _pendingDate(item),
    // The item comes in as an argument: its own changes are not read.
    reads: const {Topic.recurring},
  );

  DateTime? _pendingDate(Recurring item) {
    if (!item.active) return null;
    final now = DateTime.utc(_today().year, _today().month);
    var month = _firstOpenMonth(item);
    // Bounded: ten years of months at most.
    for (var k = 0; k < 120 && !month.isAfter(now); k++) {
      final days = _unpostedIn(item, month.year, month.month);
      if (days.isNotEmpty) return days.first;
      month = DateTime.utc(month.year, month.month + 1);
    }
    return null;
  }

  /// The first month whose days [item] can still be due on: that of its
  /// latest booking, or this month when it has none. A day before it is
  /// never asked for again.
  DateTime _firstOpenMonth(Recurring item) {
    DateTime? latest;
    // Exception to as-of-today: a booking written ahead, 預定, still books its
    // day.
    for (final e in _entries.all) {
      if (e.recurring == item.id &&
          (latest == null || e.date.isAfter(latest))) {
        latest = e.date;
      }
    }
    final from = latest ?? _today();
    return DateTime.utc(from.year, from.month);
  }

  /// The days of [year]/[month] [item] falls due that no booking of that
  /// month settles: bookings count against its days in order, and a day
  /// let go is not among them.
  List<DateTime> _unpostedIn(Recurring item, int year, int month) {
    final dates = item.dueIn(year, month);
    final booked = confirmationsIn(item, year, month).length;
    return booked < dates.length ? dates.sublist(booked) : const [];
  }

  /// Every day from [from] to [to] (both counted) [item] falls due and is
  /// not booked or let go, earliest first; none for a paused item. The
  /// same days [pendingDate] counts, so what the reminders and the
  /// calendar say is still to book is what the recurring page says.
  List<DateTime> unpostedDates(
    Recurring item, {
    required DateTime from,
    required DateTime to,
  }) {
    if (!item.active) return const [];
    var month = DateTime.utc(from.year, from.month);
    final open = _firstOpenMonth(item);
    if (month.isBefore(open)) month = open;
    final found = <DateTime>[];
    // Bounded: ten years of months at most.
    for (var k = 0; k < 120 && !month.isAfter(to); k++) {
      for (final d in _unpostedIn(item, month.year, month.month)) {
        if (!d.isBefore(from) && !d.isAfter(to)) found.add(d);
      }
      month = DateTime.utc(month.year, month.month + 1);
    }
    return found;
  }

  /// The next day [item] falls due, this month or later.
  DateTime? nextDate(Recurring item) {
    final pending = pendingDate(item);
    if (pending != null) return pending;
    for (var k = 1; k <= 24; k++) {
      final month = DateTime.utc(_today().year, _today().month + k);
      final dates = item.datesIn(month.year, month.month);
      if (dates.isNotEmpty) return dates.first;
    }
    return null;
  }

  /// Active items whose day has come this month but are not yet booked.
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

  /// The day of its recurring item [e] booked: its place among that
  /// month's bookings, in order, against the days the item falls due.
  DateTime? dueDayOf(Entry e) {
    final id = e.recurring;
    if (id == null) return null;
    final item = _recurring.byId(id);
    if (item == null) return null;
    final booked = confirmationsIn(item, e.date.year, e.date.month);
    final at = booked.indexWhere((b) => b.id == e.id);
    final days = item.dueIn(e.date.year, e.date.month);
    return at < 0 || at >= days.length ? null : days[at];
  }

  /// [item]'s amount in whole NT$ at today's rate; 0 without one.
  int worth(Recurring item) =>
      _market.toHome(item.amount, _accounts.resolve(item.account).currency) ??
      0;

  /// The entry that books [item] on its pending day, or today if that is
  /// later, for the composer to show before it is saved. A foreign one
  /// takes its worth at today's rate.
  Entry booking(Recurring item) {
    final date = pendingDate(item) ?? _today();
    final currency = _accounts.resolve(item.account).currency;
    return Entry(
      id: '',
      date: date.isAfter(_today()) ? _today() : date,
      type: item.income ? EntryType.income : EntryType.expense,
      amount: item.amount,
      account: item.account,
      category: item.category,
      note: item.name,
      recurring: item.id,
      merchant: item.merchant,
      home: currency == homeCode ? null : _market.toHome(item.amount, currency),
    );
  }
}
