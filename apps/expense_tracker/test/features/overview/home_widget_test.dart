import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/preferences.dart';
import 'package:expense_tracker/src/features/overview/model/home_widget.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing.
final class _Nowhere implements Journal {
  @override
  Future<void> keep(Batch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  final day = DateTime.utc(2026, 10, 20);

  Ledger book({List<Budget> budgets = const []}) => Ledger(
    today: day,
    accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
    categories: const [Category('飲食', 'food', Color(0xFF5C9A83))],
    entries: [
      Entry(
        id: 'rent',
        date: day,
        type: EntryType.expense,
        amount: 12345,
        account: 'bank',
        category: '飲食',
      ),
    ],
    holdings: const [],
    budgets: budgets,
    recurring: const [],
    journal: _Nowhere(),
  );

  const total = Budget(Ledger.allSpending, 20000);

  test('no figures are kept until chosen', () {
    expect(widgetSnapshot(book(), WidgetFigures.off), isNull);
  });

  test('amounts: the month spent, the budget, the pace and the week', () {
    // 2026-10-20 is a Tuesday: Monday spent nothing, Wednesday on is to come.
    expect(widgetSnapshot(book(budgets: [total]), WidgetFigures.amounts), {
      'v': 2,
      'month': '2026-10',
      'title': '10 月支出',
      'figure': '12,345',
      'budget': '預算 20,000',
      'detail': '剩 7,655',
      'progress': 62,
      'pace': 65,
      'week': [0, 100, -1, -1, -1, -1, -1],
      'weekTotal': '12,345',
      'today': 1,
      'shortLabel': '10 月預算剩',
      'shortFigure': '7,655',
    });
    final over = widgetSnapshot(
      book(budgets: [const Budget(Ledger.allSpending, 10000)]),
      WidgetFigures.amounts,
    );
    expect(over?['detail'], '超支 2,345');
    expect(over?['progress'], 100);
    expect(over?['shortLabel'], '10 月超支');
    expect(over?['shortFigure'], '2,345');
    final none = widgetSnapshot(book(), WidgetFigures.amounts);
    expect(none?['detail'], '沒有設定每月總預算');
    expect(none?['budget'], '');
    expect(none?['progress'], isNull);
    expect(none?['pace'], isNull);
    expect(none?['shortLabel'], '10 月支出');
    expect(none?['shortFigure'], '12,345');
  });

  test('percent keeps no amount at all', () {
    final snapshot = widgetSnapshot(
      book(budgets: [total]),
      WidgetFigures.percent,
    );
    expect(snapshot?['figure'], '已用 62%');
    expect(snapshot?['weekTotal'], '');
    expect(snapshot?['week'], [0, 100, -1, -1, -1, -1, -1]);
    expect(jsonEncode(snapshot), isNot(contains('12')));
    expect(widgetSnapshot(book(), WidgetFigures.percent)?['figure'], '—');
  });

  test('the file follows the choice, and the widget is told', () async {
    final directory = Directory.systemTemp.createTempSync('home-widget-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/widget.json')
      ..writeAsStringSync('{"left":"by an earlier run"}');
    final preferences = Preferences();
    var refreshed = 0;
    final widget = HomeWidget(
      file,
      preferences,
      refresh: () async => refreshed++,
      wait: Duration.zero,
    );
    final ledger = book(budgets: [total]);
    widget.follow(ledger);
    await widget.update();
    // Nothing chosen: the earlier file is removed.
    expect(file.existsSync(), isFalse);
    expect(refreshed, 1);

    preferences.update(widgetFigures: WidgetFigures.amounts);
    await widget.update();
    expect(
      jsonDecode(file.readAsStringSync()),
      containsPair('figure', '12,345'),
    );
    expect(refreshed, 2);
    // Unchanged: not written or told again.
    await widget.update();
    expect(refreshed, 2);

    widget.stop();
  });
}
