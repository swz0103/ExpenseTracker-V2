import 'dart:convert';
import 'dart:io';

import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/core/platform/preference_choices.dart';
import 'package:expense_tracker/src/features/overview/model/home_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/src/features/overview/ui/overview.dart'
    show widgetBookOf;

/// Keeps nothing.
final class _Nowhere implements LedgerDataSource {
  @override
  Future<void> keep(WriteBatch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  final day = DateTime.utc(2026, 10, 20);

  Ledger book({List<Budget> budgets = const []}) => Ledger(
    today: day,
    accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
    categories: [Category('飲食', 'food', 0xFF5C9A83)],
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
    dataSource: _Nowhere(),
  );

  const total = Budget(allSpending, 20000);

  test('no figures are kept until chosen', () {
    expect(widgetSnapshot(widgetBookOf(book()), WidgetFigures.off), isNull);
  });

  test('amounts: the month spent, the budget, the pace and the week', () {
    // 2026-10-20 is a Tuesday: Sunday and Monday spent nothing, Wednesday
    // on is to come.
    expect(
      widgetSnapshot(
        widgetBookOf(book(budgets: [total])),
        WidgetFigures.amounts,
      )?..remove('ahead'),
      {
        'v': 2,
        'month': '2026-10',
        'date': '2026-10-20',
        'title': '10 月支出',
        'figure': '12,345',
        'budget': '預算 20,000',
        'detail': '剩 7,655',
        // 12,345 of 20,000 is under the 80% warning share.
        'state': 'within',
        'progress': 62,
        'pace': 65,
        'week': [0, 0, 100, -1, -1, -1, -1],
        'weekTotal': '12,345',
        'today': 2,
        'shortLabel': '10 月預算剩',
        'shortFigure': '7,655',
        'stale': {'title': '本月概況', 'figure': '—', 'detail': '打開 App 更新本月數字'},
      },
    );
    final over = widgetSnapshot(
      widgetBookOf(book(budgets: [const Budget(allSpending, 10000)])),
      WidgetFigures.amounts,
    );
    expect(over?['detail'], '超支 2,345');
    expect(over?['state'], 'over');
    expect(over?['progress'], 100);
    expect(over?['shortLabel'], '10 月超支');
    expect(over?['shortFigure'], '2,345');
    final none = widgetSnapshot(widgetBookOf(book()), WidgetFigures.amounts);
    expect(none?['detail'], '沒有設定每月總預算');
    expect(none?['state'], '');
    expect(none?['budget'], '');
    expect(none?['progress'], isNull);
    expect(none?['pace'], isNull);
    expect(none?['shortLabel'], '10 月支出');
    expect(none?['shortFigure'], '12,345');
  });

  test('each later day of the month is worked out for the widget, which '
      'does no calendar or pace maths itself (NAT-1)', () {
    final ahead =
        widgetSnapshot(
              widgetBookOf(book(budgets: [total])),
              WidgetFigures.amounts,
            )!['ahead']!
            as Map<String, Object?>;
    // Written on Tuesday 2026-10-20: the 21st to the 31st.
    expect(ahead.keys, [for (var d = 21; d <= 31; d++) '2026-10-$d']);
    // Thursday, the same week: the days since spent nothing; 22 of 31
    // days is 70.97%, so the pace is 71.
    expect(ahead['2026-10-22'], {
      'week': [0, 0, 100, 0, 0, -1, -1],
      'today': 4,
      'pace': 71,
      'weekTotal': '12,345',
    });
    // Wednesday of the next week: it starts empty; 28 of 31 is 90.32%.
    expect(ahead['2026-10-28'], {
      'week': [0, 0, 0, 0, -1, -1, -1],
      'today': 3,
      'pace': 90,
      'weekTotal': '0',
    });
    expect(ahead['2026-10-31'], {
      'week': [0, 0, 0, 0, 0, 0, 0],
      'today': 6,
      'pace': 100,
      'weekTotal': '0',
    });
    // Without a budget there is no pace mark to move.
    final none =
        widgetSnapshot(widgetBookOf(book()), WidgetFigures.amounts)!['ahead']!
            as Map<String, Object?>;
    expect((none['2026-10-22']! as Map<String, Object?>)['pace'], isNull);
    // The percentage keeps no week total, then or later.
    final percent =
        widgetSnapshot(
              widgetBookOf(book(budgets: [total])),
              WidgetFigures.percent,
            )!['ahead']!
            as Map<String, Object?>;
    expect((percent['2026-10-28']! as Map<String, Object?>)['weekTotal'], '');
  });

  test('percent keeps no amount at all', () {
    final snapshot = widgetSnapshot(
      widgetBookOf(book(budgets: [total])),
      WidgetFigures.percent,
    );
    expect(snapshot?['figure'], '已用 62%');
    expect(snapshot?['weekTotal'], '');
    expect(snapshot?['week'], [0, 0, 100, -1, -1, -1, -1]);
    expect(jsonEncode(snapshot), isNot(contains('12')));
    expect(
      widgetSnapshot(widgetBookOf(book()), WidgetFigures.percent)?['figure'],
      '—',
    );
  });

  test('with amounts hidden in the app, the widget keeps no amount '
      'either: nothing is written (AND-06)', () {
    final ledger = book(budgets: [total]);
    final widgetBook = widgetBookOf(ledger);
    expect(widgetBook.amountsHidden, isFalse);
    ledger.amounts.toggle();
    expect(widgetBook.amountsHidden, isTrue);
    expect(widgetSnapshot(widgetBook, WidgetFigures.amounts), isNull);
    ledger.amounts.toggle();
    expect(
      widgetSnapshot(widgetBook, WidgetFigures.amounts)?['figure'],
      '12,345',
    );
  });

  test('the percentage holds no amount, so hiding amounts leaves it', () {
    final ledger = book(budgets: [total]);
    ledger.amounts.toggle();
    final snapshot = widgetSnapshot(
      widgetBookOf(ledger),
      WidgetFigures.percent,
    );
    expect(snapshot?['figure'], '已用 62%');
    expect(jsonEncode(snapshot), isNot(contains('12')));
  });

  test('hiding amounts in the app takes the file with them off the phone, '
      'and showing them writes it again', () async {
    final directory = Directory.systemTemp.createTempSync('home-widget-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/widget.json');
    final preferences = Preferences()
      ..update(widgetFigures: WidgetFigures.amounts);
    var refreshed = 0;
    final widget = HomeWidget(
      file,
      preferences,
      refresh: () async => refreshed++,
      wait: Duration.zero,
    );
    final ledger = book(budgets: [total]);
    widget.follow(widgetBookOf(ledger));
    await widget.update();
    expect(file.readAsStringSync(), contains('12,345'));
    expect(refreshed, 1);

    // The eye is closed: the change alone is followed.
    ledger.amounts.toggle();
    await Future<void>.delayed(Duration.zero);
    await widget.update();
    expect(file.existsSync(), isFalse, reason: 'no amount left on disk');
    expect(refreshed, 2);
    expect(
      [for (final f in directory.listSync()) f.path],
      isEmpty,
      reason: 'nor in a file left beside it',
    );

    ledger.amounts.toggle();
    await Future<void>.delayed(Duration.zero);
    await widget.update();
    expect(file.readAsStringSync(), contains('12,345'));
    expect(refreshed, 3);
    widget.stop();
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
    widget.follow(widgetBookOf(ledger));
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
