import 'package:flutter/painting.dart';

import '../charts/chart_data.dart';

/// What the home screen shows, in whole NT$.
final class HomeData {
  HomeData({
    required this.today,
    required this.month,
    required this.budget,
    required List<int> days,
    required List<CategorySlice> categories,
    required Map<String, int> lastMonth,
    required List<Holding> holdings,
    required List<DayEntries> week,
  }) : days = List.unmodifiable(days),
       categories = List.unmodifiable(categories),
       lastMonth = Map.unmodifiable(lastMonth),
       holdings = List.unmodifiable(holdings),
       week = List.unmodifiable(week);

  final DateTime today;

  /// This month so far.
  final MonthPoint month;
  final int budget;

  /// Spending on each day of this month so far, the 1st first.
  final List<int> days;

  /// This month's spending by category, largest first.
  final List<CategorySlice> categories;

  /// Last month's spending by category name.
  final Map<String, int> lastMonth;

  /// Largest first.
  final List<Holding> holdings;

  /// The last seven days, today last.
  final List<DayEntries> week;

  int get daysInMonth => DateTime.utc(today.year, today.month + 1, 0).day;
}

final class Holding {
  const Holding(
    this.name,
    this.code, {
    required this.value,
    required this.cost,
    required this.change,
    required this.color,
  });

  final String name;
  final String code;

  /// Market value at the last close.
  final int value;
  final int cost;

  /// Today's change in value.
  final int change;
  final Color color;

  int get gain => value - cost;
}

final class Entry {
  const Entry(
    this.title,
    this.amount, {
    required this.category,
    required this.account,
    required this.color,
    this.place = '',
    this.income = false,
  });

  final String title;
  final int amount;
  final String category;
  final String account;
  final Color color;

  /// Where it was spent, if known.
  final String place;
  final bool income;
}

final class DayEntries {
  DayEntries(this.date, List<Entry> entries)
    : entries = List.unmodifiable(entries);

  final DateTime date;
  final List<Entry> entries;

  int get spent =>
      entries.where((e) => !e.income).fold(0, (sum, e) => sum + e.amount);
}

const weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 「10月4日 週日」.
String dayLabel(DateTime date) =>
    '${date.month}月${date.day}日 週${weekdayNames[date.weekday - 1]}';
