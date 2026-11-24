import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/entries/model/compose_form.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../baseline/baseline_ledger.dart';
import '../../../support/seeded_book.dart' as seeded;

/// Every entry before the one being written, every stock's: what the sale
/// form replayed before it read one stock's trades alone (review 19 4.1).
List<Entry> _everyTradeBefore(ComposeForm form) {
  final ledger = form.ledger;
  final changed = form.editing;
  final before = <Entry>[];
  var past = false;
  for (final e in countedOn(ledger.entries.all, ledger.today)) {
    if (changed != null && e.id == changed.id) {
      past = true;
      continue;
    }
    if (e.date.isAfter(form.date)) continue;
    if (past && changed!.date == form.date && e.date == form.date) continue;
    before.add(e);
  }
  return before;
}

/// For each sale in [ledger], opened in the form, and for each method and
/// a share count about it: the cost from the stock's own trades and from
/// every trade of the book. Returns how many were compared.
int _compareSales(Ledger ledger) {
  var compared = 0;
  final sales = [
    for (final e in ledger.entries.all)
      if (e.type == EntryType.sell && e.holding != null) e,
  ];
  for (final sale in sales) {
    final form = ComposeForm(ledger, type: EntryType.sell, editing: sale);
    for (final average in [false, true]) {
      for (final shares in {sale.shares, sale.shares ~/ 2, sale.shares + 1}) {
        form
          ..average = average
          ..setShares(shares);
        final everything = ledger.holdings.saleCostWith(
          _everyTradeBefore(form),
          sale.holding!,
          shares,
          average: average,
        );
        expect(
          form.saleCost,
          everything,
          reason: '${sale.id} ${sale.holding} $shares average: $average',
        );
        compared++;
      }
    }
    // The same sale turned to another stock: the entry being changed is
    // not among that stock's trades.
    final other = sales.firstWhere(
      (e) => e.holding != sale.holding,
      orElse: () => sale,
    );
    if (other.holding != sale.holding) {
      form
        ..holding = other.holding
        ..average = false
        ..setShares(other.shares);
      expect(
        form.saleCost,
        ledger.holdings.saleCostWith(
          _everyTradeBefore(form),
          other.holding!,
          other.shares,
        ),
        reason: '${sale.id} turned to ${other.holding}',
      );
      compared++;
    }
  }
  return compared;
}

/// Two stocks traded on the same days, each sold more than once, one
/// with shares paid out (配股) between its sales.
Ledger _twoStocks() {
  Entry trade(
    String id,
    int month,
    EntryType type,
    String code,
    int amount,
    int shares,
  ) => entryOf(
    id,
    day(2026, month, 5),
    type,
    amount,
    'bank',
    holding: code,
    shares: shares,
    fee: type == EntryType.dividend ? 0 : 20,
  );
  return ledgerOf(
    today: day(2026, 9, 1),
    accounts: const [Account('bank', '銀行', AccountKind.bank, 9000000)],
    entries: [
      trade('a1', 1, EntryType.buy, '2330', 100000, 1000),
      trade('b1', 1, EntryType.buy, '0050', 50000, 1000),
      trade('a2', 2, EntryType.buy, '2330', 130000, 1000),
      trade('b2', 2, EntryType.sell, '0050', 30000, 500),
      trade('a3', 3, EntryType.sell, '2330', 90000, 700),
      // 500 shares of 0050 paid out, at no cost.
      trade('bs', 4, EntryType.dividend, '0050', 0, 500),
      trade('b3', 5, EntryType.sell, '0050', 25000, 600),
      trade('a4', 6, EntryType.sell, '2330', 150000, 1000),
      trade('b4', 6, EntryType.buy, '0050', 40000, 800),
      trade('b5', 7, EntryType.sell, '0050', 20000, 300),
    ],
  );
}

void main() {
  test("a sale costs the same from its stock's trades as from all of "
      'them: two stocks traded on the same days', () {
    // a3, a4, b2, b3, b5: five sales, two methods, up to three share
    // counts each.
    expect(_compareSales(_twoStocks()), greaterThanOrEqualTo(20));
  });

  test('… forty random books with trades, splits and reductions', () {
    var compared = 0;
    for (var seed = 1; seed <= 40; seed++) {
      compared += _compareSales(seeded.generate(seed, 160).ledger);
    }
    // Enough sales to stand for the rule, not a lucky few.
    expect(compared, greaterThan(100));
  });

  test('the cost is kept until what it rests on changes', () {
    final ledger = _twoStocks();
    final sale = ledger.entries.byId('a4')!;
    final form = ComposeForm(ledger, type: EntryType.sell, editing: sale);
    // First in, first out: 300 shares left of the 100,020 lot (30,006)
    // and 700 of the 130,020 lot (91,014): 30006 + 91014 = 121020.
    expect(form.saleCost, 121020);
    form.note = 'x';
    expect(form.saleCost, 121020);
    // 1,300 shares, all that was held then: 100020 x 300/1000 + 130020.
    form.setShares(1300);
    expect(form.saleCost, 160026);
    form.setShares(1301);
    expect(form.saleCost, isNull);
    form.setShares(1000);
    expect(form.saleCost, 121020);
  });
}
