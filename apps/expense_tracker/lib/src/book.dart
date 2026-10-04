import 'package:flutter/foundation.dart';

/// Which way money moves in an entry.
enum EntryKind { expense, income, transfer }

/// One line of the record book, in whole NT$.
final class Entry {
  const Entry(
    this.title,
    this.amount, {
    required this.kind,
    required this.category,
    required this.account,
    this.place = '',
    this.toAccount = '',
  });

  final String title;
  final int amount;
  final EntryKind kind;
  final String category;
  final String account;

  /// Where it was spent, if known.
  final String place;

  /// For a transfer, the receiving account.
  final String toAccount;
}

final class AccountLine {
  const AccountLine(this.name, this.kind, this.balance);

  final String name;

  /// 現金, 銀行, 信用卡, 電子票證 or 證券.
  final String kind;
  final int balance;
}

final class Holding {
  const Holding(
    this.name,
    this.code, {
    required this.value,
    required this.cost,
    required this.change,
  });

  final String name;
  final String code;

  /// Market value at the last close.
  final int value;
  final int cost;

  /// Today's change in value.
  final int change;

  int get gain => value - cost;
}

/// What the screens show and the entries added in this session. The
/// preview fills it with made-up data; the ledger will later.
final class Book extends ChangeNotifier {
  Book({
    required this.today,
    required this.budget,
    required Map<DateTime, List<Entry>> days,
    required List<AccountLine> accounts,
    required List<Holding> holdings,
    required List<int> investHistory,
    required List<String> reminders,
  }) : _days = {for (final e in days.entries) e.key: [...e.value]},
       accounts = List.unmodifiable(accounts),
       holdings = List.unmodifiable(holdings),
       investHistory = List.unmodifiable(investHistory),
       reminders = List.unmodifiable(reminders);

  /// Midnight UTC of the current day; every date in the book is too.
  final DateTime today;
  final int budget;
  final Map<DateTime, List<Entry>> _days;
  final List<AccountLine> accounts;

  /// Largest first.
  final List<Holding> holdings;

  /// Total market value at each recent close, oldest first.
  final List<int> investHistory;

  /// Things still to record, such as a card bill not yet paid.
  final List<String> reminders;

  /// Newest first.
  List<Entry> on(DateTime date) => List.unmodifiable(_days[date] ?? const []);

  /// Days of [year]/[month] with entries, newest first.
  List<DateTime> datesIn(int year, int month) => [
    for (final date in _days.keys)
      if (date.year == year && date.month == month && _days[date]!.isNotEmpty)
        date,
  ]..sort((a, b) => b.compareTo(a));

  /// The months that have entries, newest first, as (year, month).
  List<(int, int)> get months {
    final found = {for (final date in _days.keys) (date.year, date.month)};
    return found.toList()..sort((a, b) {
      final year = b.$1.compareTo(a.$1);
      return year != 0 ? year : b.$2.compareTo(a.$2);
    });
  }

  int total(DateTime date, EntryKind kind) => on(date)
      .where((e) => e.kind == kind)
      .fold(0, (sum, e) => sum + e.amount);

  /// Spending on each day of this month so far, the 1st first.
  List<int> get monthDays => [
    for (var day = 1; day <= today.day; day++)
      total(DateTime.utc(today.year, today.month, day), EntryKind.expense),
  ];

  int monthTotal(EntryKind kind) => [
    for (final date in datesIn(today.year, today.month)) total(date, kind),
  ].fold(0, (sum, v) => sum + v);

  int get daysInMonth => DateTime.utc(today.year, today.month + 1, 0).day;

  int get investValue => holdings.fold(0, (sum, h) => sum + h.value);

  void add(DateTime date, Entry entry) {
    (_days[date] ??= []).insert(0, entry);
    notifyListeners();
  }
}

const weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 「10/4 週日」.
String shortDay(DateTime date) =>
    '${date.month}/${date.day} 週${weekdayNames[date.weekday - 1]}';
