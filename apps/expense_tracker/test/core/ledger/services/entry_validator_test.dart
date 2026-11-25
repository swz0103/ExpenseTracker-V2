import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/messages/validation_messages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/book.dart';
import '../../../support/fuzz.dart';

void main() {
  final accounts = const [
    Account('bank', '銀行', AccountKind.bank, 1000),
    Account('card', '卡', AccountKind.card, 0, closingDay: 25, dueDay: 10),
    Account('usd', '美元', AccountKind.bank, 0, currency: 'USD'),
  ];

  String? problem(Entry e, {List<Entry> entries = const []}) => _messageOf(
    Book(accounts: accounts, entries: entries).validator.validate(e),
  );

  test('a plain entry can be kept', () {
    expect(problem(entry('a')), isNull);
  });

  test('an amount of nothing is refused', () {
    expect(problem(entry('a', amount: 0)), '請輸入金額');
  });

  test('a transfer to the same account is refused', () {
    expect(
      problem(entry('a', type: EntryType.transfer, to: 'bank')),
      '轉出與轉入不能是同一個帳戶',
    );
  });

  test('a card cannot send money out', () {
    expect(
      problem(
        entry('a', type: EntryType.transfer, account: 'card', to: 'bank'),
      ),
      '信用卡不能轉出，請記成支出',
    );
  });

  test('a foreign spending needs its worth in NT\$ until there is a rate', () {
    expect(problem(entry('a', account: 'usd')), '還沒有匯率，請輸入折合新台幣的金額');
  });

  test('a refund cannot be more than is left to refund', () {
    final bought = entry('bought', amount: 500);
    expect(
      problem(
        entry('back', type: EntryType.income, amount: 600, refundOf: 'bought'),
        entries: [bought],
      ),
      '超過可退金額 500',
    );
  });

  test('selling shares not held is refused', () {
    final sale = Entry(
      id: 's',
      date: day,
      type: EntryType.sell,
      amount: 1000,
      account: 'bank',
      holding: '2330',
      shares: 1,
    );
    expect(problem(sale), '賣出股數超過持股');
  });

  Entry trade(
    String id, {
    EntryType type = EntryType.buy,
    String account = 'bank',
    String? holding = '2330',
    int shares = 10,
    int amount = 9000,
    int tax = 0,
  }) => Entry(
    id: id,
    date: day,
    type: type,
    amount: amount,
    account: account,
    holding: holding,
    shares: shares,
    tax: tax,
  );

  test('a trade with no amount asks for shares and price', () {
    expect(problem(trade('t', amount: 0)), '請輸入股數和成交價');
  });

  test('a fee cannot be kept on money sent out of a foreign account', () {
    const usd = Account('usd2', '美元二', AccountKind.bank, 0, currency: 'USD');
    final out = Entry(
      id: 'a',
      date: day,
      type: EntryType.transfer,
      amount: 100,
      account: 'usd',
      to: 'usd2',
      fee: 5,
    );
    final book = Book(accounts: [...accounts, usd]);
    expect(_messageOf(book.validator.validate(out)), '外幣帳戶轉出時不能記手續費');
  });

  test('a card payment keeps no fee', () {
    final pay = Entry(
      id: 'a',
      date: day,
      type: EntryType.transfer,
      amount: 100,
      account: 'bank',
      to: 'card',
      fee: 15,
    );
    expect(problem(pay), '繳卡費不記手續費，請另記一筆支出');
  });

  test('money sent between currencies needs the amount received', () {
    final out = entry('a', type: EntryType.transfer, to: 'usd');
    expect(problem(out), '還沒有匯率，請輸入轉入金額');
  });

  test('a card cannot be paid straight from a foreign account', () {
    final pay = Entry(
      id: 'a',
      date: day,
      type: EntryType.transfer,
      amount: 100,
      account: 'usd',
      to: 'card',
      received: 3200,
    );
    expect(problem(pay), '外幣帳戶不能直接繳卡費');
  });

  test('shares are bought in NT\$ only, and not on a card', () {
    expect(problem(trade('t', account: 'usd')), '投資請用新台幣帳戶');
    expect(problem(trade('t', account: 'card')), '買賣股票要用現金或銀行帳戶付款');
  });

  test('a trade names its stock and its shares', () {
    expect(problem(trade('t', holding: null)), '請選擇投資標的');
    expect(problem(trade('t', shares: 0)), '請輸入股數');
    expect(problem(trade('t')), isNull);
  });

  test('the premium taken cannot be more than the dividend', () {
    final paid = trade('d', type: EntryType.dividend, shares: 0, amount: 100);
    expect(problem(paid), isNull);
    expect(
      problem(
        trade('d', type: EntryType.dividend, shares: 0, tax: 101, amount: 100),
      ),
      '補充保費不能超過股息',
    );
  });

  test('a reduction of shares cannot pass what is held, its own edit '
      'aside', () {
    final bought = trade('buy');
    final cut = trade('cut', type: EntryType.dividend, shares: -11, amount: 0);
    expect(problem(cut, entries: [bought]), '減少的股數超過持股（10 股）');
    final fine = trade('cut', type: EntryType.dividend, shares: -4, amount: 0);
    final book = Book(accounts: accounts, entries: [bought, fine]);
    // Editing the reduction counts its own four shares as still held.
    final more = trade('cut', type: EntryType.dividend, shares: -10, amount: 0);
    expect(book.validator.validate(more, replacing: fine), isNull);
  });

  test('a refund of a card spending goes back to the same card', () {
    final bought = entry('bought', account: 'card', amount: 500);
    expect(
      problem(
        entry('back', type: EntryType.income, amount: 100, refundOf: 'bought'),
        entries: [bought],
      ),
      '信用卡消費的退款要退回同一張卡',
    );
  });

  test('editing a refund counts its own amount as still refundable', () {
    final bought = entry('bought', amount: 500);
    final back = entry(
      'back',
      type: EntryType.income,
      amount: 300,
      refundOf: 'bought',
    );
    final book = Book(accounts: accounts, entries: [bought, back]);
    final raised = entry(
      'back',
      type: EntryType.income,
      amount: 500,
      refundOf: 'bought',
    );
    expect(book.validator.validate(raised, replacing: back), isNull);
    expect(book.validator.validate(raised), isA<Object>());
  });

  test('an import checks shares together, not one sale at a time', () {
    final sale = trade('s', type: EntryType.sell, shares: 1);
    final book = Book(accounts: accounts);
    expect(book.validator.validate(sale, holdings: false), isNull);
    expect(book.validator.holdsWith([trade('b'), sale]), isTrue);
    expect(book.validator.holdsWith([sale]), isFalse);
  });

  test('a save is refused while another stock stands short in the book, '
      'as the whole replay refuses it, and told again once it changes '
      '(FIX-R34)', () {
    final book = Book(
      accounts: accounts,
      entries: [
        trade('b'),
        trade('x', holding: '0050'),
      ],
    );
    final sale = trade('s', type: EntryType.sell, shares: 5);
    expect(book.validator.holdsWith([sale]), isTrue);
    // A sale of 0050 the book was given without a replay: 11 of 10 held.
    book.entries.add(
      trade('short', type: EntryType.sell, holding: '0050', shares: 11),
    );
    expect(book.validator.holdsWith([sale]), isFalse);
    expect(book.holdings.holdsWith([...book.entries.all, sale]), isFalse);
    // That sale gone, the book stands again.
    book.entries.removeWhere((e) => e.id == 'short');
    expect(book.validator.holdsWith([sale]), isTrue);
  });

  group('trades checked one after another (review 32 1.6)', () {
    Entry stock(
      String id,
      String code,
      int date, {
      EntryType type = EntryType.buy,
      int shares = 10,
    }) => Entry(
      id: id,
      date: DateTime.utc(2026, 1, date),
      type: type,
      amount: type == EntryType.dividend ? 0 : 1000,
      account: 'bank',
      holding: code,
      shares: shares,
    );

    Ledger bookOf(List<Entry> entries) => Ledger(
      today: DateTime.utc(2026, 3),
      accounts: accounts,
      categories: const [],
      entries: entries,
      holdings: const [],
      budgets: const [],
      recurring: const [],
    );

    test('a sale is held to its stock, then to what was added', () {
      final run = bookOf([stock('b', '2330', 1), stock('x', '0050', 1)])
          .entryValidator
          .tradeRun();
      // 10 held; a sale of 10 holds, a second of 1 then does not.
      final first = stock('s1', '2330', 2, type: EntryType.sell);
      expect(run.holds(first), isTrue);
      run.add(first);
      expect(
        run.holds(stock('s2', '2330', 3, type: EntryType.sell, shares: 1)),
        isFalse,
      );
      // Another stock's shares are its own.
      expect(run.holds(stock('s3', '0050', 3, type: EntryType.sell)), isTrue);
    });

    test('prepared after the book opens, every stock is answered ahead, '
        'one a step, each on the very list a later save asks about '
        '(PERF-3)', () async {
      final ledger = bookOf([
        stock('b', '2330', 1, shares: 50),
        stock('x', '0050', 1),
        entry('lunch', amount: 80),
        stock('y', '2412', 2),
      ]);
      final asked = _AskedHoldings(ledger.holdings);
      final validator = EntryValidator(
        entries: ledger.entries,
        accounts: ledger.accounts,
        holdings: asked,
        entryQueryService: ledger.entryQueryService,
        balanceService: ledger.balanceService,
      );
      final steps = <String>[];
      asked.told = steps.add;
      await validator.prepare(() async => steps.add('pause'));
      // The index first, then the three stocks in the order first written,
      // each after a pause of its own: four pauses.
      expect(steps, [
        'pause',
        'pause',
        'kept 2330',
        'pause',
        'kept 0050',
        'pause',
        'kept 2412',
      ]);
      final prepared = [...asked.keptLists];
      steps.clear();
      asked.keptLists.clear();
      // A sale of 2330 replays its own stock; the other two are asked on
      // the lists prepared, so answered as kept, not replayed again.
      final sale = stock('s', '2330', 5, type: EntryType.sell, shares: 50);
      expect(validator.holdsWith([sale]), isTrue);
      expect(steps, ['kept 0050', 'kept 2412', 'whole 2330']);
      expect(identical(asked.keptLists[0], prepared[1]), isTrue);
      expect(identical(asked.keptLists[1], prepared[2]), isTrue);
    });

    test('a stock a buy left short refuses every later sale, as the whole '
        'replay does', () {
      // 50 bought, then a sale of 100 the book holds short (left out as
      // read), then a sale of 50 that holds.
      final ledger = bookOf([
        stock('b', '2330', 1, shares: 50),
        stock('short', '2330', 10, type: EntryType.sell, shares: 100),
        stock('later', '2330', 30, type: EntryType.sell, shares: 50),
        stock('x', '0050', 1),
      ]);
      final run = ledger.entryValidator.tradeRun();
      // A buy of 50 on the 5th lets the short sale take all 100: the sale
      // of the 30th is then short, and no sale of any stock holds.
      final buy = stock('more', '2330', 5, shares: 50);
      run.add(buy);
      final other = stock('s', '0050', 20, type: EntryType.sell, shares: 1);
      expect(ledger.entryValidator.holdsWith([buy, other]), isFalse);
      expect(run.holds(other), isFalse);
    });

    for (var seed = 0; seed < fuzzSeeds; seed++) {
      test('answers as the whole replay does ($seed)', () {
        final r = Random(seed);
        const codes = ['2330', '0050', '2412'];
        var serial = 0;
        Entry any() {
          final code = codes[r.nextInt(codes.length)];
          final date = 1 + r.nextInt(28);
          return switch (r.nextInt(7)) {
            0 ||
            1 => stock('t${serial++}', code, date, shares: 1 + r.nextInt(30)),
            2 || 3 => stock(
              't${serial++}',
              code,
              date,
              type: EntryType.sell,
              shares: 1 + r.nextInt(30),
            ),
            // A capital reduction, a stock dividend, a cash dividend.
            4 => stock(
              't${serial++}',
              code,
              date,
              type: EntryType.dividend,
              shares: -(1 + r.nextInt(10)),
            ),
            5 => stock(
              't${serial++}',
              code,
              date,
              type: EntryType.dividend,
              shares: 1 + r.nextInt(5),
            ),
            _ => stock(
              't${serial++}',
              code,
              date,
              type: EntryType.dividend,
              shares: 0,
            ),
          };
        }

        // A book read as it was kept, short trades and all (left out),
        // with spending between.
        final ledger = bookOf([
          for (var i = 0; i < 30; i++)
            r.nextInt(4) == 0 ? entry('e$i', amount: 1 + i) : any(),
        ]);
        final validator = ledger.entryValidator;
        final run = validator.tradeRun();
        final added = <Entry>[];
        final read = [for (var i = 0; i < 40; i++) any()]
          ..sort((a, b) => a.date.compareTo(b.date));
        for (final e in read) {
          final whole = validator.holdsWith([...added, e]);
          expect(run.holds(e), whole, reason: 'seed $seed ${e.id}');
          final takes = e.type == EntryType.sell || e.isReduction;
          if (!takes || whole) {
            added.add(e);
            run.add(e);
          }
        }
      });
    }

    /// The answer of the whole book replayed with the change, as
    /// holdsWith gave it before (FIX-R34).
    bool wholeReplay(Ledger ledger, List<Entry> extra, {Entry? replacing}) =>
        ledger.holdings.holdsWith([
          for (final e in ledger.entries.all)
            if (replacing == null || e.id != replacing.id) e,
          ...extra,
        ]);

    test('a save is held to the stocks it trades; a book a stock of which '
        'stands short refuses it, as the whole replay does (FIX-R34)', () {
      final ledger = bookOf([
        stock('b', '2330', 1, shares: 50),
        stock('x', '0050', 1, shares: 10),
      ]);
      final validator = ledger.entryValidator;
      final sale = stock('s', '2330', 5, type: EntryType.sell, shares: 50);
      expect(validator.holdsWith([sale]), isTrue);
      // 50 held: 51 is short.
      expect(
        validator.holdsWith([
          stock('s', '2330', 5, type: EntryType.sell, shares: 51),
        ]),
        isFalse,
      );
      // The buy edited into another stock leaves no 2330 for the sale; the
      // buy edited in place, to 60, keeps them.
      final kept = ledger.entries.byId('b')!;
      expect(
        validator.holdsWith([
          stock('b', '0050', 1, shares: 50),
          sale,
        ], replacing: kept),
        isFalse,
      );
      expect(
        validator.holdsWith([
          stock('b', '2330', 1, shares: 60),
          sale,
        ], replacing: kept),
        isTrue,
      );
      // The buy taken away with nothing in its place leaves the sale short.
      expect(validator.holdsWith([sale], replacing: kept), isFalse);
      // An entry no replay reads holds, whatever the stocks.
      expect(validator.holdsWith([entry('lunch', amount: 80)]), isTrue);
    });

    for (var seed = 0; seed < fuzzSeeds; seed++) {
      test('a save answers as the whole replay does ($seed)', () {
        final r = Random(1000 + seed);
        const codes = ['2330', '0050', '2412'];
        var serial = 0;
        Entry any() {
          final code = codes[r.nextInt(codes.length)];
          final date = 1 + r.nextInt(28);
          return switch (r.nextInt(6)) {
            0 ||
            1 => stock('t${serial++}', code, date, shares: 1 + r.nextInt(30)),
            2 || 3 => stock(
              't${serial++}',
              code,
              date,
              type: EntryType.sell,
              shares: 1 + r.nextInt(30),
            ),
            4 => stock(
              't${serial++}',
              code,
              date,
              type: EntryType.dividend,
              shares: -(1 + r.nextInt(10)),
            ),
            _ => entry('e${serial++}', amount: 1 + r.nextInt(100)),
          };
        }

        // A book read as it was kept, short trades and all (left out).
        final ledger = bookOf([for (var i = 0; i < 30; i++) any()]);
        final validator = ledger.entryValidator;
        for (var k = 0; k < 40; k++) {
          final book = ledger.entries.all;
          final replacing = book.isNotEmpty && r.nextBool()
              ? book[r.nextInt(book.length)]
              : null;
          final change = any();
          final extra = [
            if (replacing != null)
              Entry(
                id: replacing.id,
                date: change.date,
                type: change.type,
                amount: change.amount,
                account: change.account,
                holding: change.holding,
                shares: change.shares,
              )
            else
              change,
            if (r.nextInt(4) == 0) any(),
          ];
          expect(
            validator.holdsWith(extra, replacing: replacing),
            wholeReplay(ledger, extra, replacing: replacing),
            reason: 'seed $seed step $k',
          );
          // Saved when it holds, so the next is asked of a changed book.
          if (replacing == null &&
              extra.length == 1 &&
              validator.holdsWith(extra)) {
            ledger.entryCommands.add(extra.single);
          }
        }
      });
    }
  });
}

String? _messageOf(RecordIssue? failure) =>
    failure == null ? null : validationMessage(failure);

/// The book's holdings, telling each ask of a stock's trades: `kept` for
/// one answered once per list ([HoldingReader.holdsWithKept]), `whole`
/// for one replayed with a change.
final class _AskedHoldings implements HoldingReader {
  _AskedHoldings(this._inner);

  final HoldingReader _inner;
  void Function(String step) told = (_) {};

  /// The lists asked about as kept, in order.
  final keptLists = <List<Entry>>[];

  @override
  bool holdsWithKept(List<Entry> kept) {
    keptLists.add(kept);
    told('kept ${kept.first.holding}');
    return _inner.holdsWithKept(kept);
  }

  @override
  bool holdsWith(List<Entry> entries) {
    told('whole ${entries.first.holding}');
    return _inner.holdsWith(entries);
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
