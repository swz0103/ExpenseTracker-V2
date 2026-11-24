// Books at the edges, posted and compared figure by figure (review 9's
// hand-made books, kept): refunds, splits, foreign values, instalments,
// reductions, fractional and huge lots, 預定 entries; each in parity.
import 'package:expense_tracker/src/core/ledger/journal/parity.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../baseline/baseline_ledger.dart';
import 'posted_book.dart';

const accts = [
  Account('bank', '銀行', AccountKind.bank, 200000),
  Account('cash', '現金', AccountKind.cash, 5000),
  Account('usd', '美元戶', AccountKind.bank, 500000, currency: 'USD'),
  Account('card', '信用卡', AccountKind.card, 0, closingDay: 5, dueDay: 20),
  Account(
    'ucard',
    '美元卡',
    AccountKind.card,
    0,
    currency: 'USD',
    closingDay: 10,
    dueDay: 25,
  ),
  Account('recv', '代墊款', AccountKind.receivable, 0),
  Account('loan', '貸款', AccountKind.loan, -100000),
];
final cats = [
  Category('飲食', 'food', 0xFF111111),
  Category('購物', 'bag', 0xFF333333),
  Category('薪水', 'salary', 0xFF555555, income: true),
];

Ledger book(
  List<Entry> es, {
  DateTime? today,
  List<Account> accounts = accts,
  bool strict = false,
}) {
  final l = ledgerOf(
    today: today ?? day(2026, 10, 31),
    accounts: accounts,
    categories: cats,
    rates: const {'USD': 32.0},
  );
  for (final e in es) {
    try {
      l.entryCommands.add(e);
    } on LedgerProblem {
      // Refused by the write rules, as the app would: not in the book.
    }
  }
  return l;
}

Future<void> check(String name, Ledger l) async {
  final b = await post(l);
  final p = await checkParity(
    today: figuresOf(l),
    reader: b.reader,
    shapes: b.report.shapes,
    unposted: b.report.unposted,
    everyDay: true,
  );
  expect(
    p,
    isA<InParity>(),
    reason: '$name: ${p is OutOfParity ? p.differences.join('\n') : ''}',
  );
  expect(p.figures, greaterThan(0), reason: name);
  expect(
    b.reader.trialBalance().values.every((v) => v == 0),
    isTrue,
    reason: '$name trial balance',
  );
}

int _n = 0;
Entry e(
  DateTime d,
  EntryType t,
  int amount,
  String account, {
  String category = '飲食',
  String? to,
  String? holding,
  int shares = 0,
  int fee = 0,
  int tax = 0,
  int installments = 0,
  bool split = false,
  bool average = false,
  int? home,
  int? received,
  String? refundOf,
  List<(String, int)> parts = const [],
  String? id,
}) => entryOf(
  id ?? 'e${_n++}',
  d,
  t,
  amount,
  account,
  category: category,
  to: to,
  holding: holding,
  shares: shares,
  fee: fee,
  tax: tax,
  installments: installments,
  split: split,
  average: average,
  home: home,
  received: received,
  refundOf: refundOf,
  parts: parts,
);

void main() {
  breaks();
  test('refund of refund', () async {
    final x = e(day(2026, 9, 1), EntryType.expense, 1000, 'bank', id: 'x');
    final r = e(
      day(2026, 9, 2),
      EntryType.income,
      400,
      'bank',
      refundOf: 'x',
      id: 'r',
    );
    final rr = e(
      day(2026, 9, 3),
      EntryType.income,
      100,
      'bank',
      refundOf: 'r',
      id: 'rr',
    );
    await check('refund of refund', book([x, r, rr]));
  });

  test('split + foreign + instalments', () async {
    final l = book([
      e(
        day(2026, 9, 1),
        EntryType.expense,
        30000,
        'ucard',
        installments: 3,
        home: 960,
        parts: [('飲食', 10000), ('購物', 20000)],
        id: 'sf',
      ),
      e(
        day(2026, 9, 2),
        EntryType.expense,
        30000,
        'ucard',
        installments: 3,
        parts: [('飲食', 10000), ('購物', 20000)],
        home: null,
        id: 'sf2',
      ),
      e(
        day(2026, 9, 3),
        EntryType.expense,
        3000,
        'card',
        installments: 6,
        parts: [('飲食', 1000), ('購物', 2000)],
        id: 'sc',
      ),
      e(
        day(2026, 9, 4),
        EntryType.expense,
        1001,
        'card',
        installments: 3,
        id: 'odd',
      ),
    ]);
    await check('split+foreign+inst', l);
  });

  test('refund of instalment purchase and of split', () async {
    final l = book([
      e(
        day(2026, 9, 3),
        EntryType.expense,
        3000,
        'card',
        installments: 3,
        id: 'i',
      ),
      e(
        day(2026, 9, 5),
        EntryType.income,
        1000,
        'card',
        refundOf: 'i',
        id: 'ri',
      ),
      e(
        day(2026, 9, 6),
        EntryType.expense,
        3000,
        'bank',
        parts: [('飲食', 1000), ('購物', 2000)],
        id: 'sp',
      ),
      e(
        day(2026, 9, 7),
        EntryType.income,
        2500,
        'bank',
        category: '購物',
        refundOf: 'sp',
        id: 'rsp',
      ),
      e(day(2026, 9, 7), EntryType.expense, 2000, 'usd', home: 64, id: 'fu'),
      e(
        day(2026, 9, 8),
        EntryType.income,
        1000,
        'usd',
        home: 31,
        refundOf: 'fu',
        id: 'rfu',
      ),
    ]);
    await check('refunds', l);
  });

  test('sell all then dividend; reduction to zero', () async {
    final l = book([
      e(
        day(2026, 8, 1),
        EntryType.buy,
        100000,
        'bank',
        holding: '2330',
        shares: 1000,
        fee: 142,
        id: 'b1',
      ),
      e(
        day(2026, 8, 2),
        EntryType.buy,
        50000,
        'bank',
        holding: '2330',
        shares: 500,
        fee: 71,
        id: 'b2',
      ),
      e(
        day(2026, 9, 1),
        EntryType.sell,
        160000,
        'bank',
        holding: '2330',
        shares: 1500,
        fee: 228,
        tax: 480,
        id: 's1',
      ),
      e(
        day(2026, 9, 2),
        EntryType.dividend,
        3000,
        'bank',
        holding: '2330',
        id: 'd1',
      ),
      e(
        day(2026, 9, 3),
        EntryType.dividend,
        0,
        'bank',
        holding: '2330',
        shares: 100,
        id: 'd2',
      ), // shares with none held
      e(
        day(2026, 9, 4),
        EntryType.sell,
        5000,
        'bank',
        holding: '2330',
        shares: 100,
        id: 's2',
      ),
    ]);
    await check('sell all then dividend', l);
  });

  test('capital reduction to zero', () async {
    final l = book([
      e(
        day(2026, 8, 1),
        EntryType.buy,
        100000,
        'bank',
        holding: '1101',
        shares: 1000,
        id: 'b1',
      ),
      e(
        day(2026, 8, 2),
        EntryType.buy,
        30000,
        'bank',
        holding: '1101',
        shares: 300,
        id: 'b2',
      ),
      e(
        day(2026, 9, 1),
        EntryType.dividend,
        140000,
        'bank',
        holding: '1101',
        shares: -1300,
        id: 'red',
      ),
      e(
        day(2026, 9, 2),
        EntryType.buy,
        10000,
        'bank',
        holding: '1101',
        shares: 100,
        id: 'b3',
      ),
      e(
        day(2026, 9, 3),
        EntryType.dividend,
        5000,
        'bank',
        holding: '1101',
        shares: -50,
        id: 'red2',
      ),
    ]);
    await check('reduction to zero', l);
    final l2 = book([
      e(
        day(2026, 8, 1),
        EntryType.buy,
        100000,
        'bank',
        holding: '1101',
        shares: 1000,
        id: 'b1',
      ),
      e(
        day(2026, 9, 1),
        EntryType.dividend,
        40000,
        'bank',
        holding: '1101',
        shares: -1000,
        id: 'red',
      ),
    ]);
    await check('reduction to zero (not covering cost)', l2);
  });

  test('split fractions across lots', () async {
    final l = book([
      e(
        day(2026, 8, 1),
        EntryType.buy,
        1000,
        'bank',
        holding: '9',
        shares: 1,
        id: 'a',
      ),
      e(
        day(2026, 8, 2),
        EntryType.buy,
        1000,
        'bank',
        holding: '9',
        shares: 1,
        id: 'b',
      ),
      e(
        day(2026, 8, 3),
        EntryType.buy,
        1000,
        'bank',
        holding: '9',
        shares: 1,
        id: 'c',
      ),
      e(
        day(2026, 8, 4),
        EntryType.dividend,
        0,
        'bank',
        holding: '9',
        shares: 1,
        split: true,
        id: 'split',
      ),
      e(
        day(2026, 8, 5),
        EntryType.sell,
        4000,
        'bank',
        holding: '9',
        shares: 4,
        id: 'sell4',
      ),
    ]);
    await check('split 4/3 then sell 4', l);
    final l2 = book([
      e(
        day(2026, 8, 1),
        EntryType.buy,
        1000,
        'bank',
        holding: '9',
        shares: 1,
        id: 'a',
      ),
      e(
        day(2026, 8, 2),
        EntryType.buy,
        1000,
        'bank',
        holding: '9',
        shares: 1,
        id: 'b',
      ),
      e(
        day(2026, 8, 3),
        EntryType.buy,
        1000,
        'bank',
        holding: '9',
        shares: 1,
        id: 'c',
      ),
      e(
        day(2026, 8, 4),
        EntryType.dividend,
        0,
        'bank',
        holding: '9',
        shares: 4,
        split: true,
        id: 'split',
      ), // 7/3
      e(
        day(2026, 8, 5),
        EntryType.sell,
        7000,
        'bank',
        holding: '9',
        shares: 7,
        id: 'sell7',
      ),
    ]);
    await check('split 7/3 then sell 7', l2);
    final l3 = book([
      e(
        day(2026, 8, 1),
        EntryType.buy,
        1000,
        'bank',
        holding: '9',
        shares: 7,
        id: 'a',
      ),
      e(
        day(2026, 8, 2),
        EntryType.buy,
        1000,
        'bank',
        holding: '9',
        shares: 11,
        id: 'b',
      ),
      e(
        day(2026, 8, 4),
        EntryType.dividend,
        0,
        'bank',
        holding: '9',
        shares: 5,
        split: true,
        id: 'split',
      ),
      e(
        day(2026, 8, 5),
        EntryType.dividend,
        0,
        'bank',
        holding: '9',
        shares: 1,
        split: true,
        id: 'split2',
      ),
      e(
        day(2026, 8, 6),
        EntryType.sell,
        4000,
        'bank',
        holding: '9',
        shares: 17,
        average: true,
        id: 'sellavg',
      ),
      e(
        day(2026, 8, 7),
        EntryType.sell,
        4000,
        'bank',
        holding: '9',
        shares: 3,
        id: 'sellfifo',
      ),
    ]);
    await check('split chain (7+11) sell', l3);
  });

  test(
    'closing day changed after instalments; account currency changed',
    () async {
      final l = book([
        e(
          day(2026, 8, 3),
          EntryType.expense,
          1800,
          'card',
          installments: 6,
          id: 'i',
        ),
        e(
          day(2026, 8, 7),
          EntryType.expense,
          900,
          'card',
          installments: 3,
          id: 'j',
        ),
        e(
          day(2026, 9, 20),
          EntryType.transfer,
          500,
          'bank',
          to: 'card',
          id: 'pay',
        ),
      ]);
      final card = l.accounts.all.firstWhere((a) => a.id == 'card');
      l.accountCommands.updateAccount(
        card.copyWith(closingDay: 25, dueDay: 10),
      );
      await check('closing day changed', l);
      final bank = l.accounts.all.firstWhere((a) => a.id == 'bank');
      l.accountCommands.updateAccount(
        Account(bank.id, bank.name, bank.kind, bank.opening, currency: 'USD'),
      );
      await check('bank currency changed', l);
    },
  );

  test('same day different orders; planned entries', () async {
    final d = day(2026, 9, 1);
    final order1 = [
      e(d, EntryType.buy, 1000, 'bank', holding: '5', shares: 1, id: 'buy'),
      e(d, EntryType.sell, 1100, 'bank', holding: '5', shares: 1, id: 'sell'),
    ];
    await check('buy then sell same day', book(order1));
    await check('sell then buy same day', book(order1.reversed.toList()));
    final future = [
      e(day(2026, 11, 15), EntryType.expense, 500, 'bank', id: 'f1'),
      e(
        day(2026, 11, 15),
        EntryType.expense,
        900,
        'card',
        installments: 3,
        id: 'f2',
      ),
      e(
        day(2026, 12, 25),
        EntryType.income,
        900,
        'bank',
        category: '薪水',
        id: 'f3',
      ),
      e(
        day(2026, 11, 1),
        EntryType.transfer,
        900,
        'bank',
        to: 'usd',
        received: 28,
        id: 'f4',
      ),
      e(day(2026, 10, 30), EntryType.expense, 100, 'bank', id: 'now'),
    ];
    await check('planned', book(future));
  });

  test('transfers across currencies and fees', () async {
    final l = book([
      e(
        day(2026, 9, 1),
        EntryType.transfer,
        3200,
        'bank',
        to: 'usd',
        received: 99,
        fee: 30,
        id: 't1',
      ),
      e(
        day(2026, 9, 2),
        EntryType.transfer,
        2000,
        'usd',
        to: 'bank',
        received: 60000,
        id: 't2',
      ),
      e(
        day(2026, 9, 3),
        EntryType.transfer,
        3200,
        'bank',
        to: 'usd',
        received: 100,
        id: 't3',
      ),
      e(day(2026, 9, 4), EntryType.transfer, 1, 'bank', to: 'cash', id: 't4'),
      e(
        day(2026, 9, 5),
        EntryType.transfer,
        5000,
        'bank',
        to: 'loan',
        id: 't5',
      ),
      e(
        day(2026, 9, 6),
        EntryType.transfer,
        5000,
        'bank',
        to: 'card',
        id: 't6',
      ),
      e(
        day(2026, 9, 7),
        EntryType.transfer,
        5000,
        'bank',
        to: 'ucard',
        received: 100,
        id: 't7',
      ),
    ]);
    await check('transfers', l);
  });

  test('foreign card statement due and instalments', () async {
    final l = book([
      e(
        day(2026, 8, 3),
        EntryType.expense,
        1800,
        'ucard',
        installments: 3,
        home: 58,
        id: 'u1',
      ),
      e(day(2026, 9, 3), EntryType.expense, 900, 'ucard', home: 29, id: 'u2'),
      e(
        day(2026, 9, 12),
        EntryType.transfer,
        2000,
        'bank',
        to: 'ucard',
        received: 60,
        id: 'pay',
      ),
      e(
        day(2026, 9, 14),
        EntryType.income,
        100,
        'ucard',
        home: 3,
        refundOf: 'u2',
        id: 'ru',
      ),
    ]);
    await check('foreign card', l);
  });

  test('opening balances: negative/zero, deleted entries', () async {
    final l = book([
      e(day(2026, 8, 3), EntryType.expense, 1800, 'recv', id: 'r1'),
      e(day(2026, 8, 3), EntryType.expense, 18000, 'loan', id: 'l1'),
      e(
        day(2026, 8, 3),
        EntryType.income,
        18000,
        'loan',
        category: '薪水',
        id: 'l2',
      ),
    ]);
    await check('loan/recv', l);
  });
}

void breaks() {
  test(
    'huge share counts, past what the old scale held (r9 break 8)',
    () async {
      for (final sh in [
        9000000000,
        10000000000,
        9300000000000,
        5000000000000000,
      ]) {
        final l = book([
          e(
            day(2026, 8, 1),
            EntryType.buy,
            1000,
            'bank',
            holding: 'H',
            shares: sh,
            id: 'b',
          ),
          e(
            day(2026, 8, 2),
            EntryType.sell,
            1000,
            'bank',
            holding: 'H',
            shares: sh ~/ 2,
            id: 's',
          ),
        ]);
        await check('huge shares $sh', l);
      }
    },
  );

  test(
    'a fractional lot, then a partial sale: exact (r9 break 7, D87)',
    () async {
      final l = book(
        [
          e(
            day(2026, 8, 1),
            EntryType.buy,
            999999999,
            'bank',
            holding: 'F',
            shares: 1,
            id: 'a',
          ),
          e(
            day(2026, 8, 1),
            EntryType.buy,
            12700,
            'bank',
            holding: 'F',
            shares: 127,
            id: 'b',
          ),
          e(
            day(2026, 8, 2),
            EntryType.dividend,
            0,
            'bank',
            holding: 'F',
            shares: 1,
            id: 'odd',
          ),
          e(
            day(2026, 8, 3),
            EntryType.sell,
            5,
            'bank',
            holding: 'F',
            shares: 1,
            id: 's1',
          ),
          e(
            day(2026, 8, 4),
            EntryType.sell,
            5,
            'bank',
            holding: 'F',
            shares: 100,
            average: true,
            id: 's2',
          ),
        ],
        accounts: [const Account('bank', '銀行', AccountKind.bank, 9999999999)],
      );
      await check('fractional lots', l);
    },
  );
  test('a foreign refund worth nothing at home (r9 break 6)', () async {
    final l = book([
      e(day(2026, 9, 1), EntryType.expense, 513, 'usd', home: 155, id: 'x'),
      e(
        day(2026, 9, 2),
        EntryType.income,
        1,
        'usd',
        home: 0,
        refundOf: 'x',
        id: 'r',
      ),
      e(day(2026, 9, 3), EntryType.expense, 1, 'usd', home: 0, id: 'z'),
    ]);
    await check('home 0', l);
  });
  test('cost left by a reduction of every share is lowered by the next '
      '(r9 break 5)', () async {
    final l = book([
      e(
        day(2026, 8, 5),
        EntryType.buy,
        328,
        'bank',
        holding: 'A',
        shares: 3,
        fee: 3,
        id: 'b1',
      ),
      e(
        day(2026, 8, 6),
        EntryType.dividend,
        143,
        'bank',
        holding: 'A',
        shares: -3,
        id: 'red1',
      ),
      e(
        day(2026, 8, 8),
        EntryType.buy,
        600,
        'bank',
        holding: 'A',
        shares: 1,
        fee: 8,
        id: 'b2',
      ),
      e(
        day(2026, 8, 10),
        EntryType.dividend,
        874,
        'bank',
        holding: 'A',
        shares: -1,
        id: 'red2',
      ),
    ]);
    await check('stranded', l);
    final l2 = book([
      e(
        day(2026, 8, 5),
        EntryType.buy,
        328,
        'bank',
        holding: 'A',
        shares: 3,
        fee: 3,
        id: 'b1',
      ),
      e(
        day(2026, 8, 6),
        EntryType.dividend,
        143,
        'bank',
        holding: 'A',
        shares: -3,
        id: 'red1',
      ),
      e(
        day(2026, 8, 8),
        EntryType.buy,
        600,
        'bank',
        holding: 'A',
        shares: 2,
        fee: 8,
        id: 'b2',
      ),
      e(
        day(2026, 8, 10),
        EntryType.sell,
        700,
        'bank',
        holding: 'A',
        shares: 1,
        id: 's',
      ),
    ]);
    await check('stranded then sell', l2);
  });

  test(
    'a 預定 payment does not count towards the statement (r9 break 4)',
    () async {
      final l = book([
        e(day(2026, 8, 20), EntryType.expense, 1000, 'card', id: 'buy'),
        // statement closed 09-05 owes 1000; today is 09-10; payment dated 09-20
        e(
          day(2026, 9, 20),
          EntryType.transfer,
          1000,
          'bank',
          to: 'card',
          id: 'pay',
        ),
      ], today: day(2026, 9, 10));
      await check('planned payment', l);
    },
  );
}
