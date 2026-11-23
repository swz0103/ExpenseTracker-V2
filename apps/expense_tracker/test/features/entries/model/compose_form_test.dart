import 'package:core/foundation_values.dart' show BusinessDate;
import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/trading.dart';
import 'package:expense_tracker/src/features/entries/model/compose_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing.
final class _Nowhere implements LedgerDataSource {
  @override
  Future<void> keep(WriteBatch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

void main() {
  final day = DateTime.utc(2026, 10, 4);

  Ledger book() => Ledger(
    today: day,
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 100000),
      Account('cash', '現金', AccountKind.cash, 2000),
    ],
    categories: [
      Category('飲食', 'food', 0xFF5C9A83),
      Category('居家', 'home', 0xFF5B8DB0),
    ],
    entries: const [],
    holdings: const [],
    budgets: const [],
    recurring: const [],
    dataSource: _Nowhere(),
  );

  test('a new expense starts on the first account, today', () {
    final form = ComposeForm(book(), type: EntryType.expense);
    expect(form.mode, ComposeMode.expense);
    expect(form.account, 'bank');
    expect(form.to, 'cash');
    expect(form.date, day);
    expect(form.amount, 0);
    expect(form.problem, isNotNull);
    form.setAmount(180);
    expect(form.sign, '−');
    expect(form.problem, isNull);
    final entry = form.build();
    expect(entry.amount, 180);
    expect(entry.account, 'bank');
    expect(entry.type, EntryType.expense);
  });

  test(
    "a trade's amount follows shares and price, and the price the amount",
    () {
      final form = ComposeForm(book(), type: EntryType.buy)..holding = '2330';
      form
        ..setShares(1000)
        ..setPrice(600.5);
      expect(form.amount, 600500);
      form.setAmount(610000);
      expect(form.price, 610);
      final (fee, tax) = form.charges;
      expect(fee, brokerFee(610000, 1000));
      expect(tax, 0);
      expect(form.settlement, 610000 + fee);
      // A fee typed from the broker's slip is kept over the suggestion.
      form.tradeFee = 500;
      expect(form.settlement, 610500);
    },
  );

  test("a trade's fee is suggested at the broker's discount given", () {
    final form = ComposeForm(book(), type: EntryType.buy, brokerDiscount: 2800)
      ..holding = '2330';
    form
      ..setShares(1000)
      ..setPrice(100);
    // 100,000 x 0.001425 = 142.5; x 0.28 = 39.9 -> 39.
    expect(form.charges, (39, 0));
    // Without one, 6折: 142.5 x 0.6 = 85.5 -> 85.
    final usual = ComposeForm(book(), type: EntryType.buy)..holding = '2330';
    usual
      ..setShares(1000)
      ..setPrice(100);
    expect(usual.charges, (85, 0));
  });

  test('a fee typed stays when the shares change; one untouched follows', () {
    // 1000 shares at 100 = 100,000; fee 85 as suggested at 6折, so the
    // saved entry reads as untouched.
    final bought = Entry(
      id: 'b',
      date: day,
      type: EntryType.buy,
      amount: 100000,
      account: 'bank',
      holding: '2330',
      shares: 1000,
      fee: 85,
    );
    final untouched = ComposeForm(book(), type: EntryType.buy, editing: bought)
      ..setShares(2000);
    // 200,000 x 0.000855 = 171.
    expect(untouched.build().fee, 171);
    // A fee of 50 was typed from the broker's slip: it stays.
    final slip = Entry(
      id: 'b',
      date: day,
      type: EntryType.buy,
      amount: 100000,
      account: 'bank',
      holding: '2330',
      shares: 1000,
      fee: 50,
    );
    final typed = ComposeForm(book(), type: EntryType.buy, editing: slip)
      ..setShares(2000);
    expect(typed.build().fee, 50);
    // Typed now, it stays through a change of price as well.
    untouched
      ..tradeFee = 120
      ..setPrice(110);
    expect(untouched.build().fee, 120);
  });

  test('a back-dated sale is costed from the lots of its day', () {
    Entry buy(String id, DateTime on, int amount) => Entry(
      id: id,
      date: on,
      type: EntryType.buy,
      amount: amount,
      account: 'bank',
      holding: '2330',
      shares: 1000,
    );
    final ledger = Ledger(
      today: day,
      accounts: const [Account('bank', '銀行', AccountKind.bank, 1000000)],
      categories: const [],
      entries: [
        buy('b1', DateTime.utc(2026, 1, 5), 100000),
        buy('b2', DateTime.utc(2026, 3, 5), 200000),
      ],
      holdings: const [],
      budgets: const [],
      recurring: const [],
      dataSource: _Nowhere(),
    );
    final form = ComposeForm(ledger, type: EntryType.sell)
      ..holding = '2330'
      ..average = true
      ..setShares(1000);
    // Today both lots: 300,000 for 2000 shares, 1000 of them 150,000.
    expect(form.saleCost, 150000);
    // On Feb 1 only the first lot was held: 1000 shares cost 100,000.
    form.date = DateTime.utc(2026, 2, 1);
    expect(form.saleCost, 100000);
    // 1500 shares were more than held then.
    form.setShares(1500);
    expect(form.saleCost, isNull);
  });

  test('a split must add up to the amount', () {
    final form = ComposeForm(book(), type: EntryType.expense)
      ..setAmount(300)
      ..category = '飲食'
      ..toggleSplit()
      ..setPart(0, 200)
      ..addPart('居家');
    expect(form.parts, [('飲食', 200), ('居家', 100)]);
    expect(form.problem, isNull);
    form.setPart(1, 50);
    expect(form.problem, contains('差 50'));
    form.evenly();
    expect(form.parts, [('飲食', 150), ('居家', 150)]);
    expect(form.build().parts, hasLength(2));
  });

  test('a split part of nothing is refused (F56)', () {
    // 300 + 0: everything shared out, then one more part with nothing.
    final form = ComposeForm(book(), type: EntryType.expense)
      ..setAmount(300)
      ..category = '飲食'
      ..toggleSplit()
      ..addPart('居家');
    expect(form.parts, [('飲食', 300), ('居家', 0)]);
    expect(form.problem, '拆分的每一項金額都要大於 0');
  });

  test('a split of one part must still add up to the amount', () {
    final form = ComposeForm(book(), type: EntryType.expense)
      ..setAmount(300)
      ..category = '飲食'
      ..toggleSplit()
      ..setAmount(500);
    // 500 − 300 = 200.
    expect(form.problem, '拆分的金額要等於總額（差 200）');
  });

  test('buying shares past the cash held warns, and may still be saved', () {
    final ledger = book();
    final form = ComposeForm(ledger, type: EntryType.buy)
      ..holding = '2330'
      ..account = 'cash'
      ..tradeFee = 20;
    form
      ..setShares(10)
      ..setPrice(300);
    // 2,000 − (3,000 + 20) = −1,020.
    expect(form.problem, isNull);
    expect(form.warning, '扣款後餘額為負（-1,020）');
    ledger.entryCommands.save(form.buildAll());
    expect(ledger.balanceService.balance('cash'), -1020);
    // Within what is held, nothing to say.
    final paid = ComposeForm(ledger, type: EntryType.buy)
      ..holding = '2330'
      ..account = 'bank'
      ..tradeFee = 20;
    paid
      ..setShares(10)
      ..setPrice(300);
    expect(paid.warning, isNull);
  });

  test('lending needs someone to lend to', () {
    final form = ComposeForm(book(), type: EntryType.expense)
      ..setAmount(500)
      ..lend(back: false);
    expect(form.tab, ComposeMode.expense);
    expect(form.problem, '請選擇代墊對象');
  });

  test('moving to another tab keeps the receipt photo only', () {
    final form = ComposeForm(book(), type: EntryType.expense)
      ..setAmount(120)
      ..receipt = 'receipt.jpg';
    form.switchTo(ComposeMode.income);
    expect(form.amount, 0);
    expect(form.receipt, 'receipt.jpg');
    expect(form.type, EntryType.income);
  });

  test('an entry opened to change reads back the same', () {
    final ledger = book();
    final saved = Entry(
      id: 'lunch',
      date: DateTime.utc(2026, 10, 2),
      type: EntryType.expense,
      amount: 95,
      account: 'cash',
      category: '飲食',
      merchant: '便當店',
      note: '午餐',
    );
    ledger.entryCommands.add(saved);
    final form = ComposeForm(ledger, type: saved.type, editing: saved);
    expect(form.more, isTrue);
    final again = form.build();
    expect(again.id, 'lunch');
    expect(
      (again.amount, again.account, again.merchant, again.note),
      (95, 'cash', '便當店', '午餐'),
    );
  });

  test('while splitting, a category is added as a part or taken away', () {
    final form = ComposeForm(book(), type: EntryType.expense)
      ..setAmount(300)
      ..category = '飲食'
      ..toggleSplit();
    expect(form.parts, [('飲食', 300)]);
    form
      ..setPart(0, 200)
      ..togglePart('居家');
    expect(form.parts, [('飲食', 200), ('居家', 100)]);
    form.togglePart('飲食');
    expect(form.parts, [('居家', 100)]);
  });

  test('a transfer turned round swaps its accounts', () {
    final form = ComposeForm(book(), type: EntryType.transfer)
      ..account = 'bank'
      ..to = 'cash'
      ..swapEnds();
    expect((form.account, form.to), ('cash', 'bank'));
  });

  test('transfers made alike twice lately are offered again', () {
    final ledger = book();
    Entry move(String id, int days, int amount) => Entry(
      id: id,
      date: day.subtract(Duration(days: days)),
      type: EntryType.transfer,
      amount: amount,
      account: 'bank',
      to: 'cash',
    );
    ledger
      ..entryCommands.add(move('a', 30, 3000))
      ..entryCommands.add(move('b', 2, 3000))
      ..entryCommands.add(move('c', 5, 800));
    final usual = ledger.entryQueryService.usualTransfers();
    expect([for (final e in usual) (e.id, e.amount)], [('b', 3000)]);
    final form = ComposeForm(ledger, type: EntryType.transfer)
      ..account = 'cash'
      ..to = 'bank'
      ..startTransferFrom(usual.single);
    expect((form.account, form.to, form.amount), ('bank', 'cash', 3000));
  });

  test('income recorded alike three times lately is offered again', () {
    final ledger = book();
    for (final (i, days) in const [5, 35, 65].indexed) {
      ledger.entryCommands.add(
        Entry(
          id: 'pay$i',
          date: day.subtract(Duration(days: days)),
          type: EntryType.income,
          amount: 52000,
          account: 'bank',
          category: '薪資',
        ),
      );
    }
    expect(ledger.entryQueryService.usual(), isEmpty);
    expect(
      [for (final e in ledger.entryQueryService.usual(income: true)) e.id],
      ['pay0'],
    );
  });

  Ledger withFriends() => book()
    ..accountCommands.addAccount(
      const Account('ann', '阿安', AccountKind.receivable, 0),
    )
    ..accountCommands.addAccount(
      const Account('bo', '小博', AccountKind.receivable, 0),
    );

  test('a spending paid partly for others is written as one', () {
    final ledger = withFriends();
    final form = ComposeForm(ledger, type: EntryType.expense)
      ..category = '飲食'
      ..lendTo(['ann', 'bo'])
      ..setAmount(1800);
    expect(form.lent, [('ann', 600), ('bo', 600)]);
    expect(form.own, 600);
    expect(form.problem, isNull);
    final made = form.buildAll();
    expect(
      [for (final e in made) (e.type, e.amount, e.to)],
      [
        (EntryType.expense, 600, null),
        (EntryType.transfer, 600, 'ann'),
        (EntryType.transfer, 600, 'bo'),
      ],
    );
    expect({for (final e in made) e.group}.single, isNotNull);
    ledger.entryCommands.addAll(made);
    expect(ledger.balanceService.balance('ann'), 600);
    expect(ledger.reportService.expense(2026, 10), 600);
    // Opened again from any of them, the whole comes back.
    final again = ComposeForm(
      ledger,
      type: EntryType.transfer,
      editing: made[2],
    );
    expect(
      (again.mode, again.amount, again.own),
      (ComposeMode.expense, 1800, 600),
    );
    expect(again.lent, [('ann', 600), ('bo', 600)]);
    again.setLent(1, 300);
    ledger.entryCommands.save(again.buildAll(), replacing: again.openedIds);
    expect(ledger.balanceService.balance('bo'), 300);
    expect(ledger.reportService.expense(2026, 10), 900);
    expect(ledger.entryQueryService.groupOf(made.first), hasLength(3));
  });

  test('all of it paid for one person is a plain 代墊', () {
    final ledger = withFriends();
    final form = ComposeForm(ledger, type: EntryType.expense)
      ..lendTo(['ann'])
      ..setAmount(500)
      ..setLent(0, 500);
    expect(form.own, 0);
    final made = form.buildAll().single;
    expect((made.type, made.to, made.group), (EntryType.transfer, 'ann', null));
    expect(form.problem, isNull);
  });

  test('paying for others and splitting do not mix', () {
    final form = ComposeForm(withFriends(), type: EntryType.expense)
      ..setAmount(300)
      ..toggleSplit()
      ..lendTo(['ann']);
    expect(form.parts, isNull);
    form.toggleSplit();
    expect(form.parts, isNull);
    expect(form.lent, [('ann', 150)]);
  });

  test('more paid for others than the whole is refused', () {
    final form = ComposeForm(withFriends(), type: EntryType.expense)
      ..setAmount(300)
      ..lendTo(['ann'])
      ..setLent(0, 400);
    expect(form.problem, '代墊的金額超過總額（多 100）');
  });

  test('對方還錢 starts with all they owe, and each sum can be left out', () {
    Entry paidFor(String id, int day, int amount) => Entry(
      id: id,
      date: DateTime.utc(2026, 10, day),
      type: EntryType.transfer,
      amount: amount,
      account: 'bank',
      to: 'ann',
    );
    final ledger = Ledger(
      today: day,
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 100000),
        Account('ann', '阿安', AccountKind.receivable, 0),
      ],
      categories: const [],
      entries: [paidFor('lunch', 1, 300), paidFor('taxi', 2, 200)],
      holdings: const [],
      budgets: const [],
      recurring: const [],
      dataSource: _Nowhere(),
    );
    final form = ComposeForm(ledger, type: EntryType.income)
      ..lend(back: true)
      ..to = 'ann'
      ..payAll();
    expect(form.paying, {'lunch', 'taxi'});
    expect(form.amount, 500);

    // The taxi left owed: only the lunch is paid back.
    form.togglePaying('taxi');
    expect(form.paying, {'lunch'});
    expect(form.amount, 300);
    // Nothing ticked pays nothing, never less.
    form.togglePaying('lunch');
    expect(form.amount, 0);
    form.togglePaying('taxi');
    expect(form.amount, 200);
  });

  test('a transfer shows what each end holds once it is made', () {
    final form = ComposeForm(book(), type: EntryType.transfer)
      ..account = 'bank'
      ..to = 'cash'
      ..setAmount(500);
    expect((form.fromAfter, form.toAfter), (99500, 2500));
    // A fee comes off the end it is paid from only.
    form.fee = 15;
    expect((form.fromAfter, form.toAfter), (99485, 2500));
  });

  test('another end works out what is received again', () {
    final form = ComposeForm(book(), type: EntryType.transfer)..received = 70;
    form.setTo('bank');
    expect((form.to, form.received), ('bank', null));
    form.received = 70;
    form.setFrom('cash');
    expect((form.account, form.received), ('cash', null));
  });

  test('the row of categories keeps the one chosen in sight', () {
    final ledger = Ledger(
      today: day,
      accounts: const [Account('bank', '銀行', AccountKind.bank, 0)],
      categories: [
        for (final n in ['飲食', '交通', '居家', '娛樂', '醫療', '教育'])
          Category(n, 'other', 0xFF000000),
      ],
      entries: const [],
      holdings: const [],
      budgets: const [],
      recurring: const [],
      dataSource: _Nowhere(),
    );
    final form = ComposeForm(ledger, type: EntryType.expense);
    final first = form.categoryRow();
    expect(first.shown, hasLength(4));
    expect(first.more, isTrue);

    // One beyond the four takes the last place.
    final last = ledger.reportService.categoriesByUse(income: false).last;
    form.category = last;
    final row = form.categoryRow();
    expect(row.shown, [...first.shown.take(3), last]);
  });

  test('splitting shows each part and what is left of the amount', () {
    final form = ComposeForm(book(), type: EntryType.expense)
      ..setAmount(1000)
      ..toggleSplit();
    form.parts = [('飲食', 600), ('居家', 300)];
    expect(form.splitLeft, 100);
    expect(form.categoryRow().shown, containsAll(['飲食', '居家']));
    expect(form.categoryRow().more, isTrue);
    form.parts = [('飲食', 700), ('居家', 400)];
    expect(form.splitLeft, -100);
  });

  test('a sale costs what was paid, first in or on average', () {
    Entry buy(String id, int d, int amount) => Entry(
      id: id,
      date: DateTime.utc(2026, 9, d),
      type: EntryType.buy,
      amount: amount,
      account: 'bank',
      holding: '2330',
      shares: 10,
    );
    final ledger = Ledger(
      today: day,
      accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
      categories: const [],
      entries: [buy('a', 1, 10000), buy('b', 2, 20000)],
      // Nothing held before: the two buys are all there is.
      holdings: const [],
      budgets: const [],
      recurring: const [],
      dataSource: _Nowhere(),
    );
    final form = ComposeForm(ledger, type: EntryType.sell)
      ..holding = '2330'
      ..shares = 10;
    expect(form.saleCost, 10000);
    form.average = true;
    expect(form.saleCost, 15000);
    // More than are held has no cost; nor has a buy, or no holding.
    form.shares = 30;
    expect(form.saleCost, isNull);
    form
      ..shares = 10
      ..trade = EntryType.buy;
    expect(form.saleCost, isNull);
    form
      ..trade = EntryType.sell
      ..holding = null;
    expect(form.saleCost, isNull);
    // Settled two exchange days on: Friday's trade on Tuesday.
    form.date = DateTime.utc(2026, 10, 2);
    expect(form.settles.value, BusinessDate(2026, 10, 6));
    // Wed 10-07: Fri 10-09 is 補假, so Mon 10-12 (decision D24).
    form.date = DateTime.utc(2026, 10, 7);
    expect(form.settles.value, BusinessDate(2026, 10, 12));
  });

  test('a dividend changes the shares held one way at a time', () {
    final form = ComposeForm(book(), type: EntryType.dividend);
    expect(form.shareChangeKind, ShareChange.none);
    for (final kind in ShareChange.values) {
      form
        ..shares = 50
        ..setShareChange(kind);
      expect(form.shareChangeKind, kind);
    }
    // None leaves no shares written.
    form.setShareChange(ShareChange.none);
    expect(form.shares, 0);
    form.setShareChange(ShareChange.capitalReduction);
    expect((form.reduce, form.splitShares), (true, false));
  });

  test('a merchant or tag tapped again is taken off', () {
    final form = ComposeForm(book(), type: EntryType.expense);
    form.toggleMerchant('便當店');
    expect(form.merchant, '便當店');
    expect(form.merchantChoices().first, '便當店');
    form.toggleMerchant('便當店');
    expect(form.merchant, '');

    form
      ..toggleTag('家用')
      ..toggleTag('旅行');
    expect(form.tags, ['家用', '旅行']);
    expect(form.tagChoices().take(2), ['家用', '旅行']);
    form.toggleTag('家用');
    expect(form.tags, ['旅行']);
  });

  test('what someone owes is told by sum, each by what it was for', () {
    final ledger = Ledger(
      today: day,
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 100000),
        Account('ann', '阿安', AccountKind.receivable, 0),
      ],
      categories: const [],
      entries: [
        Entry(
          id: 'noted',
          date: DateTime.utc(2026, 10, 1),
          type: EntryType.transfer,
          amount: 300,
          account: 'bank',
          to: 'ann',
          note: '午餐',
        ),
        Entry(
          id: 'bare',
          date: DateTime.utc(2026, 10, 2),
          type: EntryType.transfer,
          amount: 200,
          account: 'bank',
          to: 'ann',
        ),
      ],
      holdings: const [],
      budgets: const [],
      recurring: const [],
      dataSource: _Nowhere(),
    );
    final form = ComposeForm(ledger, type: EntryType.income)..to = '';
    expect(form.owedNow, 0);
    expect(form.owedSums, isEmpty);
    form.to = 'ann';
    expect(form.owedNow, 500);
    // The latest first.
    expect(
      [for (final (e, left) in form.owedSums) (e.id, left)],
      [('bare', 200), ('noted', 300)],
    );
    expect(
      [for (final (e, _) in form.owedSums) form.owedTitle(e)],
      ['代墊', '午餐'],
    );

    // A new person gets an account of their own for what they owe.
    expect(form.addPerson('  '), isNull);
    final bo = form.addPerson(' 小博 ')!;
    expect((bo.name, bo.kind), ('小博', AccountKind.receivable));
    expect(ledger.accounts.contains(bo.id), isTrue);
  });
}
