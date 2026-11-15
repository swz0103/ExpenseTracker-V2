part of 'ledger.dart';

// Fixed items: booking what falls due, skipping and bringing back a
// period, and saving or removing an item.

extension LedgerRecurring on Ledger {
  /// The day of its recurring item [e] booked: its place among that
  /// month's bookings, in order, against the days the item falls due.
  DateTime? dueDayOf(Entry e) {
    final id = e.recurring;
    if (id == null) return null;
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index < 0) return null;
    final item = _recurring[index];
    final booked = confirmationsIn(item, e.date.year, e.date.month);
    final at = booked.indexWhere((b) => b.id == e.id);
    final days = item.dueIn(e.date.year, e.date.month);
    return at < 0 || at >= days.length ? null : days[at];
  }

  /// The recurring items [removed] booked, each with the day it lets go:
  /// a booking deleted is a period skipped, not one to book again.
  List<Recurring> _skipping(List<Entry> removed) {
    final changed = <String, Recurring>{};
    for (final e in removed) {
      final day = dueDayOf(e);
      if (day == null) continue;
      final item =
          changed[e.recurring] ??
          _recurring.firstWhere((r) => r.id == e.recurring);
      changed[item.id] = item.copyWith(skipped: {...item.skipped, day});
    }
    return changed.values.toList();
  }

  /// The recurring items [back] booked with the day each had let go
  /// taken out again: the one nearest the entry in its month.
  List<Recurring> _unskipping(List<Entry> back) {
    final changed = <String, Recurring>{};
    for (final e in back) {
      final id = e.recurring;
      if (id == null) continue;
      final index = _recurring.indexWhere((r) => r.id == id);
      if (index < 0) continue;
      final item = changed[id] ?? _recurring[index];
      final days =
          [
            for (final d in item.skipped)
              if (d.year == e.date.year && d.month == e.date.month) d,
          ]..sort(
            (a, b) => (a.difference(e.date).abs()).compareTo(
              b.difference(e.date).abs(),
            ),
          );
      if (days.isEmpty) continue;
      changed[id] = item.copyWith(
        skipped: {...item.skipped}..remove(days.first),
      );
    }
    return changed.values.toList();
  }

  void _putRecurring(List<Recurring> items) {
    for (final item in items) {
      final index = _recurring.indexWhere((r) => r.id == item.id);
      if (index >= 0) _recurring[index] = item;
    }
  }

  /// Takes [day] out of [item]'s skipped days, so it is booked again: 恢復
  /// on the calendar.
  void unskip(Recurring item, DateTime day) {
    if (!item.skipped.contains(day)) return;
    saveRecurring(item.copyWith(skipped: {...item.skipped}..remove(day)));
  }

  /// [item]'s amount in whole NT$ at today's rate; 0 without one.
  int recurringWorth(Recurring item) =>
      toHome(item.amount, account(item.account).currency) ?? 0;

  /// The entry that books [item] on its pending day, or today if that is
  /// later, for the composer to show before it is saved. A foreign one
  /// takes its worth at today's rate.
  Entry booking(Recurring item) {
    final date = pendingDate(item) ?? today;
    final currency = account(item.account).currency;
    return Entry(
      id: '',
      date: date.isAfter(today) ? today : date,
      type: item.income ? EntryType.income : EntryType.expense,
      amount: item.amount,
      account: item.account,
      category: item.category,
      note: item.name,
      recurring: item.id,
      merchant: item.merchant,
      home: currency == homeCode ? null : toHome(item.amount, currency),
    );
  }

  /// Books [item] as it stands.
  void confirm(Recurring item) {
    add(booking(item).withId(newId()));
  }

  /// Books every day of the items marked [Recurring.auto] that has come
  /// and is not booked yet, on its own day, all in one change; returns
  /// how many were booked. Run when the ledger opens and when the day
  /// turns, so no background work is needed.
  int bookDue() {
    final booked = <Entry>[];
    for (final item in _recurring) {
      if (!item.auto || !item.active) continue;
      // Each booking settles one day; a missed one from last month comes
      // first. Bounded, in case an item's dates do not move on.
      final days = <DateTime>{};
      for (var i = 0; i < 62; i++) {
        final day = pendingDate(item);
        if (day == null || day.isAfter(today) || !days.add(day)) break;
        if (item.amount <= 0 ||
            !hasAccount(item.account) ||
            account(item.account).archived) {
          break;
        }
        final entry = booking(item).withId(newId());
        // Kept in the list so the next pending day counts it.
        _entries.add(entry);
        _forget(const {Topic.entries});
        booked.add(entry);
      }
    }
    if (booked.isEmpty) return 0;
    _entries.removeRange(_entries.length - booked.length, _entries.length);
    addAll(booked);
    return booked.length;
  }

  /// Puts [item] in place of the one with the same id, or adds it.
  void saveRecurring(Recurring item) {
    final index = _recurring.indexWhere((r) => r.id == item.id);
    if (index < 0) {
      _recurring.add(item);
    } else {
      _recurring[index] = item;
    }
    _changed(const {Topic.recurring});
    _keep(WriteBatch(recurring: [item]));
  }

  void removeRecurring(String id) {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index < 0) return;
    final removed = _recurring.removeAt(index);
    _changed(const {Topic.recurring});
    _keep(WriteBatch(dropped: [(Collection.recurring, removed.id)]));
  }
}
