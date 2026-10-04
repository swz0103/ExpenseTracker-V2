import 'dart:math';

import 'package:flutter/painting.dart';

/// What the charts draw, in whole NT$. Charts only show money; the exact
/// amounts stay in the ledger.
final class ChartData {
  ChartData({
    required List<MonthPoint> months,
    required List<List<CategorySlice>> categories,
    required List<List<int>> days,
  }) : months = List.unmodifiable(months),
       categories = List.unmodifiable(categories),
       days = List.unmodifiable(days) {
    if (categories.length != months.length || days.length != months.length) {
      throw ArgumentError('Every month needs its categories and days');
    }
  }

  /// Oldest first.
  final List<MonthPoint> months;

  /// Each month's spending by category, largest first.
  final List<List<CategorySlice>> categories;

  /// Each month's spending per day, the 1st first; days still to come in
  /// the current month are left out.
  final List<List<int>> days;
}

final class MonthPoint {
  const MonthPoint(
    this.year,
    this.month, {
    required this.income,
    required this.expense,
    required this.netWorth,
  });

  final int year;
  final int month;
  final int income;
  final int expense;

  /// At the end of the month.
  final int netWorth;

  int get net => income - expense;

  String get label => '$month月';
}

final class CategorySlice {
  const CategorySlice(
    this.name,
    this.amount,
    this.color, {
    this.children = const [],
  });

  final String name;
  final int amount;
  final Color color;

  /// Subcategories, largest first; empty when there are none.
  final List<CategorySlice> children;
}

/// Colours shared by the charts, close to the old app's.
abstract final class ChartColors {
  static const income = Color(0xFF4B7A45);
  static const expense = Color(0xFFC1502E);
  static const netWorth = Color(0xFF5B6B52);
  static const accent = Color(0xFF7C5FA3);
}

/// `1234567` → `1,234,567`.
String groupDigits(int value) {
  final digits = value.abs().toString();
  final grouped = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return grouped.toString();
}

/// Short axis labels: `8500` → `8.5千`, `125000` → `12.5萬`.
String compactAmount(int value) {
  final size = value.abs();
  String scaled(int unit, String name) {
    final text = (value / unit).toStringAsFixed(1);
    final trimmed = text.endsWith('.0')
        ? text.substring(0, text.length - 2)
        : text;
    return '$trimmed$name';
  }

  if (size >= 100000000) return scaled(100000000, '億');
  if (size >= 10000) return scaled(10000, '萬');
  if (size >= 1000) return scaled(1000, '千');
  return '$value';
}

/// A round grid spacing (1, 2 or 5 times a power of ten) so that [lines]
/// lines of it reach at least [top].
int gridStep(int top, int lines) {
  final raw = max(1, (top / lines).ceil());
  var unit = 1;
  while (unit * 10 <= raw) {
    unit *= 10;
  }
  for (final multiple in const [1, 2, 5]) {
    if (unit * multiple >= raw) return unit * multiple;
  }
  return unit * 10;
}
