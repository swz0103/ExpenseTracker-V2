import 'package:expense_tracker/src/core/ledger/journal.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing: the ledger's own work is what is timed.
final class _Nowhere implements Journal {
  @override
  Future<void> keep(Batch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

/// Ten thousand entries over three years, as a heavy user would have:
/// spending in cash, by bank and on a card (some in instalments), salary,
/// card payments, monthly buys of three stocks and their dividends. Each
/// step a screen takes is timed and held to a bound far above what it
/// takes, so the test catches a step that grows out of hand (work done
/// for every entry for every entry) without failing on a slow machine.
void main() {
  final today = DateTime.utc(2026, 10, 27);
  const count = 10000;
  const days = 1095;
  const spending = ['飲食', '居家', '交通', '購物', '娛樂', '醫療'];
  const stocks = ['2330', '0050', '00679B'];

  List<Entry> entries() {
    final list = <Entry>[];
    var n = 0;
    String id() => 'e${n++}';
    // Each month: salary, the card paid, a buy of each stock; each July
    // after the first year, a dividend of each.
    for (var k = 35; k >= 0; k--) {
      DateTime on(int day) => DateTime.utc(today.year, today.month - k, day);
      list.add(
        Entry(
          id: id(),
          date: on(5),
          type: EntryType.income,
          amount: 52000,
          account: 'bank',
          category: '薪資',
        ),
      );
      list.add(
        Entry(
          id: id(),
          date: on(10),
          type: EntryType.transfer,
          amount: 15000,
          account: 'bank',
          category: transferCategory,
          to: 'card',
        ),
      );
      for (final code in stocks) {
        list.add(
          Entry(
            id: id(),
            date: on(15),
            type: EntryType.buy,
            amount: 10000,
            account: 'bank',
            category: '投資',
            holding: code,
            shares: 100,
            fee: 14,
          ),
        );
        if (on(1).month == 7 && k < 24) {
          list.add(
            Entry(
              id: id(),
              date: on(20),
              type: EntryType.dividend,
              amount: 1200,
              account: 'bank',
              category: '股息收入',
              holding: code,
            ),
          );
        }
      }
    }
    // The rest spending, spread evenly over the three years.
    final rest = count - list.length;
    for (var i = 0; i < rest; i++) {
      final date = today.subtract(Duration(days: days - 1 - i * days ~/ rest));
      final account = const ['cash', 'bank', 'card'][i % 3];
      list.add(
        Entry(
          id: id(),
          date: date,
          type: EntryType.expense,
          amount: 40 + i * 37 % 300,
          account: account,
          category: spending[i % spending.length],
          merchant: i % 4 == 0 ? '便利商店${i % 20}' : '',
          note: i.isEven ? '午餐' : '',
          tags: i % 7 == 0 ? const ['家用'] : const [],
          installments: account == 'card' && i % 97 == 0 ? 6 : 0,
        ),
      );
    }
    return list..sort((a, b) => a.date.compareTo(b.date));
  }

  Ledger book(List<Entry> list) => Ledger(
    today: today,
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 300000),
      Account('cash', '現金', AccountKind.cash, 5000),
      Account('card', '信用卡', AccountKind.card, 0, closingDay: 25, dueDay: 10),
    ],
    categories: [
      for (final (i, name) in spending.indexed)
        Category(name, 'other', Color(0xFF5C9A83 + i)),
      const Category('薪資', 'income', Color(0xFF5B8DB0), income: true),
    ],
    entries: list,
    holdings: const [],
    budgets: const [],
    recurring: const [],
    journal: _Nowhere(),
  );

  test('ten thousand entries stay quick on every screen', () async {
    final list = entries();
    expect(list, hasLength(count));
    final timings = <String, int>{};
    T timed<T>(String name, T Function() work, {required int under}) {
      final watch = Stopwatch()..start();
      final result = work();
      watch.stop();
      timings[name] = watch.elapsedMilliseconds;
      expect(
        watch.elapsedMilliseconds,
        lessThan(under),
        reason: '$name took ${watch.elapsedMilliseconds} ms',
      );
      return result;
    }

    final months = [
      for (var k = 0; k < 36; k++) DateTime.utc(today.year, today.month - k),
    ];

    // Opening: every trade replayed, every balance ready to ask for.
    final ledger = timed('open', () => book(list), under: 3000);
    timed('balances', () {
      for (final a in ledger.accounts) {
        ledger.balance(a.id);
      }
      return ledger.assets;
    }, under: 2000);

    // 總覽 and 紀錄 for each month, as switching months back three years.
    timed('switch 36 months', () {
      for (final m in months) {
        ledger.entriesIn(m.year, m.month);
        ledger.expense(m.year, m.month);
        ledger.income(m.year, m.month);
      }
    }, under: 2000);

    // 財務報表: a year's categories, merchants and tags, and the net worth
    // at the end of each month.
    timed('reports', () {
      final from = DateTime.utc(today.year - 1, today.month);
      ledger
        ..spendingBetween(from, today)
        ..merchantsBetween(from, today)
        ..tagsBetween(from, today);
      for (final m in months.take(12)) {
        ledger.netWorthAt(DateTime.utc(m.year, m.month + 1, 0));
      }
    }, under: 4000);

    // The card's statement and what is still unbilled.
    final card = ledger.account('card');
    timed('card', () {
      ledger
        ..statementDue(card)
        ..unbilled(card)
        ..instalmentsOn(card);
    }, under: 2000);

    timed('search', () => ledger.search('午餐'), under: 2000);

    // One entry saved, then the month it is in, the balances and the
    // card shown again: the work redone for one change.
    timed('save one and show it', () {
      ledger.add(
        Entry(
          id: 'new',
          date: today,
          type: EntryType.expense,
          amount: 120,
          account: 'card',
          category: '飲食',
        ),
      );
      ledger
        ..entriesIn(today.year, today.month)
        ..expense(today.year, today.month)
        ..balance('card')
        ..statementDue(card);
    }, under: 2000);
    await ledger.settled;

    debugPrint(
      '一萬筆：${[for (final MapEntry(:key, :value) in timings.entries) '$key $value ms'].join('、')}',
    );
  });
}
