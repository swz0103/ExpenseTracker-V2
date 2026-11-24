import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show Listenable, VoidCallback;

import '../../../../design_system/display/amount.dart';
import '../../../../design_system/display/status.dart';

import 'package:core/foundation_values.dart'
    show BusinessDate, YearMonth, startOfWeek, weekdayIndex;

import '../../../core/ledger/ledger.dart';
import '../../../core/platform/preferences.dart';
import '../../../core/diagnostics/error_log.dart';

import 'package:core/time/utc_days.dart';

/// The parts of the ledger the home-screen widget is written from, its
/// clock, and its changes to follow
/// (docs/adr/0013-models-take-what-they-use.md).
final class WidgetBook implements Listenable {
  WidgetBook({
    required this._changes,
    required this._clock,
    required this.reportService,
    required this.budgets,
    required this.budgetService,
    this._amountsHidden,
  });

  final Listenable _changes;
  final DateTime Function() _clock;

  /// The app's 隱藏金額 switch, read each time; never hidden when none.
  final bool Function()? _amountsHidden;

  /// Whether amounts are hidden in the app now: the widget then keeps
  /// none either.
  bool get amountsHidden => _amountsHidden?.call() ?? false;
  final ReportService reportService;
  final BudgetReader budgets;
  final BudgetService budgetService;

  /// The ledger's today, read each time.
  DateTime get today => _clock();

  @override
  void addListener(VoidCallback listener) => _changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);
}

/// What the home-screen widget 本月概況 shows for [figures], as the text it
/// shows and nothing more; null when it shows no figures. With
/// [WidgetFigures.percent] no amount is kept at all: the share of the
/// month's total budget used, and this week's days only as heights.
///
/// This is the one place that decides what leaves the encrypted book for
/// the home screen, which anyone holding the phone sees, locked or not:
/// nothing until the person chose a level ([WidgetFigures]), amounts only
/// under [WidgetFigures.amounts], and none of them while amounts are
/// hidden in the app ([WidgetBook.amountsHidden]). Whatever is not
/// allowed is never written, so it is not on disk in plain form; the
/// widget draws what is written and decides nothing.
///
/// `budget` and `detail` sit under the budget bar, left and right;
/// `pace` is how far through the month today is, a mark on that bar;
/// `week` is each day from Sunday as a share of the week's largest day,
/// -1 for days still to come; `shortLabel` and `shortFigure` are what the
/// widget shows when made small; `date` is the day it was written, so the
/// widget can move the week on by itself when the app is not opened.
Map<String, Object?>? widgetSnapshot(WidgetBook book, WidgetFigures figures) {
  if (figures == WidgetFigures.off) return null;
  if (figures == WidgetFigures.amounts && book.amountsHidden) return null;
  final today = book.today;
  final m = today.month;
  final month = YearMonth(today.year, m).toString();
  final date = BusinessDate.of(today).toString();
  final spent = book.reportService.expense(today.year, m);
  final whole = _wholeBudget(book);
  final allowance = whole == null
      ? null
      : book.budgetService.allowance(whole, today.year, today.month);
  final hasBudget = allowance != null && allowance > 0;
  // Decided by the budget rules, worded by the status presentation: the
  // widget shows these words and colours by `state`.
  final status = hasBudget
      ? budgetStatus(
          spent: spent,
          limit: allowance,
          warningPercent: whole!.warning,
        )
      : null;
  final over = status is BudgetOver;
  final state = status == null ? '' : budgetLook(status).id;
  final used = hasBudget ? percent(spent, allowance) : null;
  final days = monthEnd(today.year, m).day;
  final pace = hasBudget ? percent(today.day, days) : null;
  // The same days as 總覽's week, from Sunday.
  final first = startOfWeek(BusinessDate.of(today)).asUtcMidnight;
  final daySpent = [
    for (var i = 0; i < 7; i++)
      book.reportService.spentOn(first.add(Duration(days: i))),
  ];
  final weekday = weekdayIndex(BusinessDate.of(today));
  final week = _weekHeights(daySpent, weekday);
  const noBudget = '沒有設定每月總預算';
  return switch (figures) {
    WidgetFigures.amounts => {
      'v': 2,
      'month': month,
      'date': date,
      'title': '$m 月支出',
      'figure': groupDigits(spent),
      'budget': hasBudget ? '預算 ${groupDigits(allowance)}' : '',
      'detail': status == null
          ? noBudget
          : '${budgetLead(status)} ${groupDigits(budgetFigure(status))}',
      'state': state,
      'progress': used?.clamp(0, 100),
      'pace': pace,
      'week': week,
      'weekTotal': groupDigits(daySpent.fold(0, (a, b) => a + b)),
      'today': weekday,
      'shortLabel': status == null
          ? '$m 月支出'
          : over
          ? '$m 月${StatusWords.over}'
          : '$m 月預算剩',
      'shortFigure': status == null
          ? groupDigits(spent)
          : groupDigits(budgetFigure(status)),
    },
    WidgetFigures.percent => {
      'v': 2,
      'month': month,
      'date': date,
      'title': '$m 月預算',
      'figure': used == null ? '—' : '已用 $used%',
      'budget': '',
      'detail': used == null
          ? noBudget
          : over
          ? StatusWords.over
          : '',
      'state': state,
      'progress': used?.clamp(0, 100),
      'pace': pace,
      'week': week,
      'weekTotal': '',
      'today': weekday,
      'shortLabel': '$m 月預算',
      'shortFigure': used == null ? '—' : '已用 $used%',
    },
    WidgetFigures.off => null,
  };
}

/// The budget for all spending, or null when no total budget is set.
Budget? _wholeBudget(WidgetBook book) {
  Budget? total;
  for (final b in book.budgets.all) {
    if (b.category == allSpending && b.limit > 0) total = b;
  }
  return total;
}

/// Each day of [daySpent] as a share of the week's largest day, -1 for
/// the days after [weekday].
List<int> _weekHeights(List<int> daySpent, int weekday) {
  final most = daySpent.fold(0, (a, b) => max(a, b));
  return [
    for (var i = 0; i < 7; i++)
      i > weekday
          ? -1
          : most <= 0
          ? 0
          : percent(max(daySpent[i], 0), most),
  ];
}

/// Keeps the widget's snapshot (`widget.json` beside the book) up to
/// date while the book is open, and asks the widget to show it again;
/// the widget reads only that file, so it shows the figures the person
/// chose to show while the book is locked too. With no figures to show
/// ([widgetSnapshot] gives none) the file is removed, and the widget says
/// amounts are hidden.
final class HomeWidget {
  HomeWidget(
    this._file,
    this._preferences, {
    required this._refresh,
    this._wait = const Duration(seconds: 1),
  });

  final File _file;
  final Preferences _preferences;

  /// Tells the widget to read the file again.
  final Future<void> Function() _refresh;

  /// Changes made one after another are written once.
  final Duration _wait;

  WidgetBook? _book;
  Timer? _timer;

  /// What was written last; [_written] is false until the first time, so
  /// a file left by an earlier run is replaced or removed.
  String? _last;
  var _written = false;

  void follow(WidgetBook book) {
    _book = book;
    book.addListener(_soon);
    _preferences.addListener(_soon);
    unawaited(update());
  }

  void stop() {
    _timer?.cancel();
    _book?.removeListener(_soon);
    _preferences.removeListener(_soon);
    _book = null;
  }

  void _soon() {
    _timer?.cancel();
    _timer = Timer(_wait, () => unawaited(update()));
  }

  /// Writes the snapshot when it changed, and tells the widget; one after
  /// another, so the file is never written twice at once.
  Future<void> update() => _pending = _pending.then((_) => _update());
  Future<void> _pending = Future.value();

  Future<void> _update() async {
    final book = _book;
    if (book == null) return;
    final snapshot = widgetSnapshot(book, _preferences.widgetFigures);
    final text = snapshot == null ? null : jsonEncode(snapshot);
    if (_written && text == _last) return;
    _written = true;
    _last = text;
    try {
      if (text == null) {
        if (_file.existsSync()) await _file.delete();
      } else {
        // Written beside, then renamed over: the widget never reads half.
        await _file.parent.create(recursive: true);
        final next = File(
          '${_file.path}.${Random.secure().nextInt(1 << 30)}.new',
        );
        await next.writeAsString(text, flush: true);
        await next.rename(_file.path);
      }
      await _refresh();
    } on Object catch (error) {
      ErrorLog.instance.record('桌面小工具', error);
    }
  }
}
