// Random valid books for the journal's property tests (review 5's
// generator, review 9's extended one `gen`): seeded, so a failing seed is
// a book to look at, and a shrinker that cuts one down to a minimal
// counterexample.
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/journal/parity.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';

import '../../../baseline/baseline_ledger.dart';
import 'posted_book.dart';

const accounts = [
  Account('bank', '銀行', AccountKind.bank, 200000),
  Account('cash', '現金', AccountKind.cash, 5000),
  Account('usd', '美元戶', AccountKind.bank, 500000, currency: 'USD'),
  Account('card', '信用卡', AccountKind.card, 0, closingDay: 5, dueDay: 20),
  Account('recv', '代墊款', AccountKind.receivable, 0),
];

/// The accounts held in NT$.
const ntdAccounts = ['bank', 'cash', 'card', 'recv'];

final categories = [
  Category('飲食', 'food', 0xFF111111),
  Category('早餐', 'food', 0xFF111112, parent: '飲食'),
  Category('宵夜', 'food', 0xFF111113, parent: '飲食'),
  Category('交通', 'car', 0xFF222222),
  Category('購物', 'bag', 0xFF333333),
  Category('娛樂', 'fun', 0xFF444444),
  Category('薪水', 'salary', 0xFF555555, income: true),
  Category('獎金', 'bonus', 0xFF666666, income: true),
];

const spendCats = ['飲食', '早餐', '宵夜', '交通', '購物', '娛樂'];
const shops = ['全家', '星巴克', '捷運', '7-11', '燒肉', '誠品', ''];
const tagsPool = ['日常', '旅遊', '公司', '家人'];

DateTime defaultToday = day(2026, 10, 31);

/// Budgets every book of this run starts with (set per test).
List<Budget> startBudgets = const [];

Ledger emptyBook({
  DateTime? today,
  DateTime Function()? clock,
  List<Recurring> recurring = const [],
}) => ledgerOf(
  today: today ?? defaultToday,
  clock: clock,
  accounts: accounts,
  categories: categories,
  recurring: recurring,
  budgets: startBudgets,
  rates: const {'USD': 32.0},
);

/// A book and every entry it accepted, in the order accepted.
typedef Book = ({Ledger ledger, List<Entry> log, Map<String, int> made});

/// A random valid book of about [count] entries on days 2026-06-01 ..
/// 2026-10-31. [off] switches kinds off: usd, refund, transfer, trade,
/// split, inst (instalments).
Book generate(
  int seed,
  int count, {
  Set<String> off = const {},
  DateTime? today,
}) {
  final r = Random(seed);
  final l = emptyBook(today: today);
  final log = <Entry>[];
  final made = <String, int>{};
  void note(String k) => made[k] = (made[k] ?? 0) + 1;
  final days = List.generate(
    count,
    (_) => day(2026, 6, 1).add(Duration(days: r.nextInt(153))),
  )..sort();
  int pick(int lo, int hi) => lo + r.nextInt(hi - lo + 1);
  T of<T>(List<T> xs) => xs[r.nextInt(xs.length)];
  var held = 0;
  void put(Entry e, String kind) {
    try {
      l.entryCommands.add(e);
      log.add(e);
      note(kind);
    } catch (_) {
      note('refused');
    }
  }

  for (final d in days) {
    final roll = r.nextInt(100);
    bool skip(String k) => off.contains(k);
    if ((roll >= 40 && roll < 48 && skip('usd')) ||
        (roll >= 55 && roll < 66 && skip('refund')) ||
        (roll >= 66 && roll < 80 && skip('transfer')) ||
        (roll >= 80 && roll < 92 && skip('trade'))) {
      continue;
    }
    if (roll < 40) {
      final acct = of(['bank', 'bank', 'cash', 'card']);
      final amount = pick(20, 3000);
      final split = r.nextInt(100) < 15 && amount >= 40 && !skip('split');
      final first = pick(10, amount - 10);
      final cat = of(spendCats);
      var cat2 = of(spendCats);
      if (cat2 == cat) {
        cat2 = spendCats[(spendCats.indexOf(cat) + 1) % spendCats.length];
      }
      final inst = acct == 'card' && r.nextInt(100) < 15 ? of([3, 6]) : 0;
      put(
        entryOf(
          l.newId(),
          d,
          EntryType.expense,
          amount,
          acct,
          category: cat,
          merchant: of(shops),
          tags: r.nextBool() ? [of(tagsPool)] : const [],
          installments: skip('inst') ? 0 : inst,
          parts: split ? [(cat, first), (cat2, amount - first)] : const [],
        ),
        split ? 'split' : 'expense',
      );
    } else if (roll < 48) {
      final amount = pick(500, 20000);
      final rate = 31.5 + r.nextInt(100) / 100;
      put(
        entryOf(
          l.newId(),
          d,
          EntryType.expense,
          amount,
          'usd',
          category: of(spendCats),
          merchant: of(shops),
          tags: r.nextInt(4) == 0 ? [of(tagsPool)] : const [],
          home: (amount * rate / 100).round(),
        ),
        'usd expense',
      );
    } else if (roll < 55) {
      put(
        entryOf(
          l.newId(),
          d,
          EntryType.income,
          pick(20000, 60000),
          'bank',
          category: of(['薪水', '獎金']),
        ),
        'income',
      );
    } else if (roll < 66) {
      final pool = [
        for (final x in l.entries.all)
          if (x.type == EntryType.expense &&
              !x.isRefund &&
              x.installments < 2 &&
              l.entryQueryService.refundable(x) > 0 &&
              !x.date.isAfter(d))
            x,
      ];
      if (pool.isEmpty) continue;
      final o = of(pool);
      final left = l.entryQueryService.refundable(o);
      final amount = r.nextBool() ? left : pick(1, left);
      final home = o.home == null
          ? null
          : (o.home! * amount / o.amount).round();
      put(
        entryOf(
          l.newId(),
          d,
          EntryType.income,
          amount,
          o.account,
          category: o.category,
          home: home,
          refundOf: o.id,
          merchant: '',
        ),
        'refund',
      );
    } else if (roll < 80) {
      switch (r.nextInt(5)) {
        case 0:
          put(
            entryOf(
              l.newId(),
              d,
              EntryType.transfer,
              pick(100, 5000),
              'bank',
              to: 'cash',
              fee: r.nextInt(3) == 0 ? 15 : 0,
            ),
            'transfer',
          );
        case 1:
          put(
            entryOf(
              l.newId(),
              d,
              EntryType.transfer,
              pick(100, 3000),
              'bank',
              to: 'card',
            ),
            'transfer',
          );
        case 2:
          put(
            entryOf(
              l.newId(),
              d,
              EntryType.transfer,
              pick(100, 2000),
              'bank',
              to: 'recv',
            ),
            'transfer',
          );
        case 3:
          if (skip('usd')) continue;
          final cents = pick(2000, 30000);
          put(
            entryOf(
              l.newId(),
              d,
              EntryType.transfer,
              (cents * 0.32).round(),
              'bank',
              to: 'usd',
              received: cents,
              fee: r.nextInt(4) == 0 ? 30 : 0,
            ),
            'transfer',
          );
        default:
          put(
            entryOf(
              l.newId(),
              d,
              EntryType.transfer,
              pick(100, 1500),
              'cash',
              to: 'bank',
            ),
            'transfer',
          );
      }
    } else if (roll < 92) {
      final sell = held >= 1000 && r.nextBool();
      final shares = sell ? 1000 * pick(1, held ~/ 1000) : 1000 * pick(1, 3);
      final price = 500 + r.nextInt(300);
      final e = entryOf(
        l.newId(),
        d,
        sell ? EntryType.sell : EntryType.buy,
        shares * price,
        'bank',
        category: investmentCategory,
        holding: '2330',
        shares: shares,
        fee: (shares * price * 0.001425).round(),
        tax: sell ? (shares * price * 0.003).round() : 0,
      );
      try {
        l.entryCommands.add(e);
        log.add(e);
        held += sell ? -shares : shares;
        note(sell ? 'sell' : 'buy');
      } catch (_) {
        note('refused');
      }
    }
  }
  return (ledger: l, log: log, made: made);
}

/// A book from [entries], each added if the ledger accepts it; [clock]
/// optionally moves "today".
Ledger replay(
  List<Entry> entries, {
  DateTime? today,
  DateTime Function()? clock,
  List<Recurring> recurring = const [],
}) {
  final l = emptyBook(today: today, clock: clock, recurring: recurring);
  for (final e in entries) {
    try {
      l.entryCommands.add(e);
    } catch (_) {}
  }
  return l;
}

/// Cuts [entries] down while [fails] (given the rebuilt book) stays true:
/// chunks first, then one by one.
List<Entry> shrink(
  List<Entry> entries,
  bool Function(Ledger) fails, {
  DateTime? today,
}) {
  var cur = [...entries];
  bool bad(List<Entry> es) {
    // A refund keeps its original: no orphans in a counterexample.
    final ids = {for (final e in es) e.id};
    if (es.any((e) => e.refundOf != null && !ids.contains(e.refundOf))) {
      return false;
    }
    try {
      return fails(replay(es, today: today));
    } catch (_) {
      return false;
    }
  }

  var chunk = cur.length ~/ 2;
  while (chunk >= 1) {
    var i = 0;
    var progressed = false;
    while (i < cur.length) {
      final tryList = [...cur]..removeRange(i, min(i + chunk, cur.length));
      if (tryList.length < cur.length && bad(tryList)) {
        cur = tryList;
        progressed = true;
      } else {
        i += chunk;
      }
    }
    if (!progressed || chunk == 1) chunk ~/= 2;
  }
  return cur;
}

String show(Entry e) =>
    '${e.date.toIso8601String().substring(0, 10)} ${e.type.name} ${e.amount}'
    ' ${e.account}${e.to != null ? '->${e.to}' : ''}'
    '${e.category.isEmpty ? '' : ' [${e.category}]'}'
    '${e.fee != 0 ? ' fee${e.fee}' : ''}${e.tax != 0 ? ' tax${e.tax}' : ''}'
    '${e.installments > 1 ? ' x${e.installments}' : ''}'
    '${e.home != null ? ' home${e.home}' : ''}'
    '${e.received != null ? ' recv${e.received}' : ''}'
    '${e.refundOf != null ? ' refund' : ''}'
    '${e.parts.isNotEmpty ? ' parts${e.parts}' : ''}'
    '${e.tags.isNotEmpty ? ' #${e.tags.join(',')}' : ''}'
    '${e.merchant.isNotEmpty ? ' @${e.merchant}' : ''}'
    '${e.shares != 0 ? ' sh${e.shares}' : ''}';

const _seeds40 = [
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
  26,
  27,
  28,
  29,
  30,
  31,
  32,
  33,
  34,
  35,
  36,
  37,
  38,
  39,
  40,
];

/// Runs [check] on seeds [seeds]; for the first failing seed prints the
/// message, shrinks the book to a minimal counterexample and prints it.
/// Returns a failure text, or null when the invariant held on every seed.
String? property(
  String name,
  String? Function(Ledger) check, {
  Iterable<int> seeds = _seeds40,
  int count = 200,
  Set<String> off = const {},
  DateTime? today,
  void Function(String)? log,
}) {
  final failing = <int>[];
  String? first;
  Book? firstBook;
  for (final s in seeds) {
    final b = generate(s, count, off: off, today: today);
    final msg = check(b.ledger);
    if (msg != null) {
      failing.add(s);
      if (first == null) {
        first = msg;
        firstBook = b;
      }
    }
  }
  final out = StringBuffer(
    '[$name] seeds tried ${seeds.length}, '
    'failing ${failing.length} $failing',
  );
  if (first != null) {
    final small = shrink(firstBook!.log, (l) => check(l) != null, today: today);
    final msg = check(replay(small, today: today));
    out.writeln();
    out.writeln('  first failure (unshrunk): $first');
    out.writeln(
      '  minimal book (${small.length} entries, shrunk from ${firstBook.log.length}):',
    );
    for (final e in small) {
      out.writeln('    ${show(e)}');
    }
    out.write('  on the minimal book: $msg');
  }
  // ignore: avoid_print
  print(out);
  return first == null ? null : out.toString();
}

Future<String?> diff(Ledger l) async {
  final b = await post(l);
  final p = await checkParity(
    today: figuresOf(l),
    reader: b.reader,
    shapes: b.report.shapes,
    unposted: b.report.unposted,
    everyDay: true,
  );
  if (p is OutOfParity) {
    return p.differences.take(5).map((d) => '$d').join('\n');
  }
  return null;
}

final accts = [
  ...accounts,
  const Account(
    'ucard',
    '美元卡',
    AccountKind.card,
    0,
    currency: 'USD',
    closingDay: 10,
    dueDay: 25,
  ),
  const Account('loan', '貸款', AccountKind.loan, -100000),
];

Ledger fresh(DateTime today) => ledgerOf(
  today: today,
  accounts: accts,
  categories: categories,
  rates: const {'USD': 32.0},
);

/// Extended generator: several stocks with splits, stock dividends,
/// reductions, average cost, foreign cards, instalments, same-day order.
(Ledger, List<Entry>) gen(int seed, int count, DateTime today) {
  final r = Random(seed);
  final l = fresh(today);
  final log = <Entry>[];
  var n = 0;
  int pick(int lo, int hi) => lo + r.nextInt(hi - lo + 1);
  T of<T>(List<T> xs) => xs[r.nextInt(xs.length)];
  final held = <String, int>{};
  final codes = ['2330', '0050', '9'];
  void put(Entry e) {
    try {
      l.entryCommands.add(e);
      log.add(e);
    } catch (_) {}
  }

  final days = List.generate(
    count,
    (_) => day(2026, 8, 1).add(Duration(days: r.nextInt(110))),
  )..sort();
  for (final d in days) {
    final id = 'x${n++}';
    final roll = r.nextInt(100);
    if (roll < 20) {
      final acct = of(['bank', 'card', 'ucard', 'usd', 'cash']);
      final foreign = acct == 'ucard' || acct == 'usd';
      final amount = foreign ? pick(100, 90000) : pick(1, 5000);
      final split = r.nextInt(100) < 30 && amount >= 4;
      final first = amount > 1 ? pick(1, amount - 1) : 1;
      final inst = (acct == 'card' || acct == 'ucard') && r.nextInt(100) < 30
          ? of([2, 3, 7, 12, 60])
          : 0;
      put(
        entryOf(
          id,
          d,
          EntryType.expense,
          amount,
          acct,
          category: of(spendCats),
          installments: inst,
          home: foreign ? (amount * 0.3).round() + 1 : null,
          parts: split && !foreign
              ? [('飲食', first), ('購物', amount - first)]
              : const [],
        ),
      );
    } else if (roll < 28) {
      put(
        entryOf(
          id,
          d,
          EntryType.income,
          pick(1, 99999),
          'bank',
          category: '薪水',
        ),
      );
    } else if (roll < 40) {
      final pool = [
        for (final x in l.entries.all)
          if ((x.type == EntryType.expense || x.isRefund) &&
              l.entryQueryService.refundable(x) > 0 &&
              !x.date.isAfter(d))
            x,
      ];
      if (pool.isEmpty) continue;
      final o = of(pool);
      final left = l.entryQueryService.refundable(o);
      final amt = r.nextBool() ? left : pick(1, left);
      put(
        entryOf(
          id,
          d,
          EntryType.income,
          amt,
          o.account,
          category: o.category,
          home: o.home == null ? null : (o.home! * amt / o.amount).round(),
          refundOf: o.id,
        ),
      );
    } else if (roll < 55) {
      final from = of(['bank', 'cash', 'usd', 'card', 'ucard', 'recv', 'loan']);
      final to = of(['bank', 'cash', 'usd', 'card', 'ucard', 'recv', 'loan']);
      final cross =
          (from == 'usd' || from == 'ucard') != (to == 'usd' || to == 'ucard');
      put(
        entryOf(
          id,
          d,
          EntryType.transfer,
          pick(1, 9000),
          from,
          to: to,
          fee: r.nextInt(3) == 0 ? pick(1, 50) : 0,
          received: cross ? pick(1, 9000) : null,
        ),
      );
    } else {
      final code = of(codes);
      final h = held[code] ?? 0;
      final k = r.nextInt(100);
      Entry? e;
      int delta = 0;
      if (k < 35) {
        final sh = of([1, 2, 3, 7, 1000, 1500]);
        e = entryOf(
          id,
          d,
          EntryType.buy,
          sh * pick(10, 900),
          'bank',
          holding: code,
          shares: sh,
          fee: pick(0, 30),
          category: '投資',
        );
        delta = sh;
      } else if (k < 60 && h > 0) {
        final sh = pick(1, h);
        e = entryOf(
          id,
          d,
          EntryType.sell,
          sh * pick(10, 900),
          'bank',
          holding: code,
          shares: sh,
          fee: pick(0, 30),
          tax: pick(0, 30),
          average: r.nextBool(),
          category: '投資',
        );
        delta = -sh;
      } else if (k < 70) {
        e = entryOf(
          id,
          d,
          EntryType.dividend,
          pick(1, 30000),
          'bank',
          holding: r.nextInt(5) == 0 ? null : code,
          tax: 0,
          category: '投資',
        );
      } else if (k < 82 && h > 0) {
        final sh = pick(1, 5);
        final split = r.nextBool();
        e = entryOf(
          id,
          d,
          EntryType.dividend,
          0,
          'bank',
          holding: code,
          shares: sh,
          split: split,
          category: '投資',
        );
        delta = sh; // approximate
      } else if (h > 0) {
        final sh = pick(1, h);
        e = entryOf(
          id,
          d,
          EntryType.dividend,
          pick(0, 5000),
          'bank',
          holding: code,
          shares: -sh,
          category: '投資',
        );
        delta = -sh;
      }
      if (e == null) continue;
      try {
        l.entryCommands.add(e);
        log.add(e);
        held[code] = max(0, h + delta);
        if (delta > 0 && e.shares > 0 && e.type == EntryType.dividend) {
          held[code] = l.holdings.byCode(code)?.shares ?? 0;
        }
      } catch (_) {
        held[code] = l.holdings.byCode(code)?.shares ?? 0;
      }
    }
  }
  return (l, log);
}
