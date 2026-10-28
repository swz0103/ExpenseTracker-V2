import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../../core/ledger/amounts.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/perf.dart';
import '../../../core/preferences.dart';

/// What the home-screen widget 本月概況 shows for [figures], as the text it
/// shows and nothing more; null when it shows no figures. With
/// [WidgetFigures.percent] no amount is kept at all, only the share of the
/// month's total budget used.
Map<String, Object?>? widgetSnapshot(Ledger ledger, WidgetFigures figures) {
  if (figures == WidgetFigures.off) return null;
  final today = ledger.today;
  final month = '${today.year}-${today.month.toString().padLeft(2, '0')}';
  final spent = ledger.expense(today.year, today.month);
  Budget? total;
  for (final b in ledger.budgets) {
    if (b.category == Ledger.allSpending && b.limit > 0) total = b;
  }
  final allowance = total == null
      ? null
      : ledger.allowance(total, today.year, today.month);
  final used = allowance == null || allowance <= 0
      ? null
      : (spent * 100 / allowance).round();
  const noBudget = '沒有設定每月總預算';
  return switch (figures) {
    WidgetFigures.amounts => {
      'v': 1,
      'month': month,
      'title': '${today.month} 月支出',
      'figure': groupDigits(spent),
      'detail': allowance == null
          ? noBudget
          : spent <= allowance
          ? '預算剩 ${groupDigits(allowance - spent)}'
          : '超支 ${groupDigits(spent - allowance)}',
      'progress': used?.clamp(0, 100),
    },
    WidgetFigures.percent => {
      'v': 1,
      'month': month,
      'title': '${today.month} 月預算',
      'figure': used == null ? '—' : '已用 $used%',
      'detail': used == null ? noBudget : '',
      'progress': used?.clamp(0, 100),
    },
    WidgetFigures.off => null,
  };
}

/// Keeps the widget's snapshot (`widget.json` beside the ledger) up to
/// date while the ledger is open, and asks the widget to show it again;
/// the widget reads only that file, so it shows the figures while the
/// ledger is locked. With no figures chosen the file is removed.
final class HomeWidget {
  HomeWidget(
    this._file,
    this._preferences, {
    required Future<void> Function() refresh,
    Duration wait = const Duration(seconds: 1),
  }) : _refresh = refresh,
       _wait = wait;

  final File _file;
  final Preferences _preferences;

  /// Tells the widget to read the file again.
  final Future<void> Function() _refresh;

  /// Changes made one after another are written once.
  final Duration _wait;

  Ledger? _ledger;
  Timer? _timer;

  /// What was written last; [_written] is false until the first time, so
  /// a file left by an earlier run is replaced or removed.
  String? _last;
  var _written = false;

  void follow(Ledger ledger) {
    _ledger = ledger;
    ledger.addListener(_soon);
    _preferences.addListener(_soon);
    unawaited(update());
  }

  void stop() {
    _timer?.cancel();
    _ledger?.removeListener(_soon);
    _preferences.removeListener(_soon);
    _ledger = null;
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
    final ledger = _ledger;
    if (ledger == null) return;
    final snapshot = widgetSnapshot(ledger, _preferences.widgetFigures);
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
      Perf.instance.problem('桌面小工具', error);
    }
  }
}
