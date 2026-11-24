// Round 6 support: state fingerprints (every shown number + every record),
// a book builder with recurring items, and a shrinker that keeps the setup.
import 'dart:convert';
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/record_json.dart';

import '../baseline/baseline_ledger.dart';
import 'book_records.dart';
import 'invariant_book.dart';

export '../baseline/baseline_ledger.dart';
export 'book_records.dart';
export 'invariant_book.dart';

DateTime last(int m) => day(2026, m + 1, 0);
DateTime first(int m) => day(2026, m, 1);

const rentItem = Recurring(
  id: 'rent',
  name: '房租',
  amount: 500,
  day: 5,
  account: 'bank',
  category: '購物',
  auto: true,
);

final recurringItems = [
  Recurring(
    id: 'rent',
    name: '房租',
    amount: 500,
    day: 5,
    account: 'bank',
    category: '購物',
    auto: true,
    start: DateTime.utc(2026, 6, 5),
  ),
  Recurring(
    id: 'sub',
    name: '訂閱',
    amount: 300,
    day: 12,
    account: 'cash',
    category: '娛樂',
    start: DateTime.utc(2026, 8, 12),
  ),
  Recurring(
    id: 'pay',
    name: '薪資',
    amount: 40000,
    day: 25,
    account: 'bank',
    category: '薪水',
    income: true,
    auto: true,
    start: DateTime.utc(2026, 7, 25),
  ),
];

/// Seeded book with 3 recurring items, the auto ones booked.
Ledger book(int seed, {int count = 120, bool recurring = true}) {
  final l = generate(seed, count).ledger;
  if (recurring) addRecurring(l);
  return l;
}

void addRecurring(Ledger l) {
  for (final r in recurringItems) {
    l.recurringCommands.saveRecurring(r);
  }
  l.recurringCommands.bookDue();
}

/// Rebuilds a book from accepted entries plus the recurring setup.
Ledger rebuild(List<Entry> es, {bool recurring = true}) {
  final l = replay(es);
  if (recurring) addRecurring(l);
  return l;
}

/// When set, the list-valued figures that are sets to the person (tags,
/// merchants, categories by use) are compared sorted; tie order is
/// reported separately.
bool listsAsSets = false;
String _l(Object? list) => listsAsSets
    ? '${([for (final x in list! as List) '$x']..sort())}'
    : '$list';

/// Every number the screens show, plus recurring state.
Map<String, String> stats(Ledger l) {
  final out = <String, String>{};
  final b = l.balanceService, r = l.reportService;
  for (final a in l.accounts.all) {
    out['bal:${a.id}'] = '${b.balance(a.id)}';
    out['bal:${a.id}@8/31'] = '${b.balance(a.id, until: last(8))}';
    out['weekly:${a.id}'] = '${b.weeklyChanges(a.id)}';
  }
  for (var m = 6; m <= 10; m++) {
    out['nw:$m'] = '${b.netWorthAt(last(m))}';
    out['inc:$m'] = '${r.income(2026, m)}';
    out['exp:$m'] = '${r.expense(2026, m)}';
    out['div:$m'] = '${r.dividends(2026, m)}';
    final cats = r.spendingBetween(first(m), last(m));
    for (final k in cats.keys) {
      out['cat:$m:$k'] = '${cats[k]}';
    }
    for (final (n, c, v) in r.merchantsBetween(first(m), last(m))) {
      out['merch:$m:$n'] = '$c/$v';
    }
    for (final (n, v) in r.tagsBetween(first(m), last(m))) {
      out['tag:$m:$n'] = '$v';
    }
    for (final bud in l.budgets.all) {
      out['budget:$m:${bud.category}'] =
          '${l.budgetService.spentAgainst(bud, 2026, m)}';
    }
    out['budgetFood:$m'] =
        '${l.budgetService.spentAgainst(const Budget('飲食', 1), 2026, m)}';
    out['tagBudget:$m'] = '${l.budgetService.spentOnTag('旅遊', 2026, m)}';
  }
  for (final (n, c, v) in r.merchantStats) {
    out['merchAll:$n'] = '$c/$v';
  }
  for (final (n, c, v) in r.tagStats) {
    out['tagAll:$n'] = '$c/$v';
  }
  out['tags'] = _l(r.tags);
  out['merchants'] = _l(l.entryQueryService.merchants);
  for (final m in l.entryQueryService.merchants) {
    out['lastAt:$m'] = '${l.entryQueryService.categoryAt(m)}';
  }
  out['usual'] = _l([for (final e in l.entryQueryService.usual()) show(e)]);
  out['usualIncome'] = _l([
    for (final e in l.entryQueryService.usual(income: true)) show(e),
  ]);
  out['usualTransfers'] = _l([
    for (final e in l.entryQueryService.usualTransfers()) show(e),
  ]);
  out['catsByUse'] = _l(r.categoriesByUse(income: false));
  for (final a in l.accounts.all.where((a) => a.kind == AccountKind.card)) {
    out['card:${a.id}:due'] = '${l.statementService.statementDue(a)}';
    out['card:${a.id}:unbilled'] =
        '${l.statementService.unbilled(a).fold(0, (s, e) => s + e.amount)}';
    out['card:${a.id}:inst'] = '${l.statementService.instalmentsOn(a).length}';
  }
  for (final a in l.accounts.all.where(
    (a) => a.kind == AccountKind.receivable,
  )) {
    out['owed:${a.id}'] =
        '${r.owedBy(a.id).fold(0, (s, x) => s + x.$2)}/${r.owedBy(a.id).length}';
  }
  out['assets'] = '${b.assets}';
  out['cardDebt'] = '${b.cardDebt}';
  for (final h in l.holdings.all) {
    out['hold:${h.code}'] =
        'shares ${h.shares} cost ${h.cost} realized ${h.realized} div ${h.dividends}';
  }
  final rs = l.recurringService;
  for (final it in l.recurring.all) {
    out['rec:${it.id}:pending'] = '${rs.pendingDate(it)}';
    out['rec:${it.id}:next'] = '${rs.nextDate(it)}';
    out['rec:${it.id}:skipped'] = '${(it.skipped.toList()..sort())}';
  }
  out['rec:due'] = '${rs.due.map((r) => r.id).toList()..sort()}';
  out['rec:upcoming'] = '${rs.upcoming.map((r) => r.id).toList()..sort()}';
  out['problems'] = '${l.integrityService.problems().length}';
  return out;
}

/// Records (sorted, order not compared) as a flat map; [trash] false drops
/// the trash and the receipts-of-trash.
Map<String, String> records(Ledger l, {bool trash = true, bool order = false}) {
  final m = bookRecords(l);
  final out = <String, String>{};
  for (final k in m.keys) {
    if (!order && k.startsWith('order')) continue;
    if (!trash && (k == 'trash' || k == 'order of trash')) continue;
    out[k] = m[k]!.join('\n');
  }
  return out;
}

/// Records and statistics together, keys prefixed.
Map<String, String> state(Ledger l, {bool trash = true, bool order = false}) =>
    {
      for (final e in records(l, trash: trash, order: order).entries)
        'rec/${e.key}': e.value,
      for (final e in stats(l).entries) 'stat/${e.key}': e.value,
    };

String? diff(
  Map<String, String> a,
  Map<String, String> b, {
  String an = 'before',
  String bn = 'after',
}) {
  final keys = {...a.keys, ...b.keys}.toList()..sort();
  final bad = [
    for (final k in keys)
      if (a[k] != b[k]) '$k: $an ${_cut(a[k])}, $bn ${_cut(b[k])}',
  ];
  if (bad.isEmpty) return null;
  return '${bad.length} differences, first: ${bad.take(5).join(' | ')}';
}

String _cut(String? s) {
  if (s == null) return 'null';
  final one = s.replaceAll('\n', ';');
  return one.length > 140 ? '${one.substring(0, 140)}...' : one;
}

/// A ledger rebuilt from [l]'s records only (no caches).
Ledger freshOf(Ledger l) => Ledger(
  today: l.today,
  accounts: l.accounts.all,
  categories: l.categories.all,
  entries: l.entries.all,
  holdings: const [],
  budgets: l.budgets.all,
  recurring: l.recurring.all,
  trash: l.trash.all,
  rates: const {'USD': 32.0},
);

const seeds = [
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
];

/// Runs [run] on up to [targets] entries of each seeded book (chosen by
/// the seed) with a fresh book for each; [run] returns a failure text or
/// null. Prints the table row, and for the first failure shrinks the book
/// (same target by id) and prints the minimal case.
String? inverse(
  String name,
  String? Function(Ledger l, Entry target) run, {
  int targets = 4,
  int count = 120,
  bool recurring = true,
  bool Function(Entry)? only,
  Iterable<int> useSeeds = seeds,
}) {
  final failing = <int>[];
  var tried = 0;
  String? first;
  Book? firstBook;
  String? firstTarget;
  for (final s in useSeeds) {
    final b = generate(s, count);
    final l0 = rebuild(b.log, recurring: recurring);
    final pool = [
      for (final e in l0.entries.all)
        if (only == null || only(e)) keyOf(e),
    ];
    final r = Random(s * 7919);
    final picked = <String>{};
    for (var i = 0; i < targets && pool.isNotEmpty; i++) {
      picked.add(pool[r.nextInt(pool.length)]);
    }
    var bad = false;
    for (final id in picked) {
      final l = rebuild(b.log, recurring: recurring);
      final t = byKey(l, id);
      if (t == null) continue;
      tried++;
      String? msg;
      try {
        msg = run(l, t);
      } catch (e, st) {
        msg = 'threw $e ${st.toString().split('\n').take(3).join(' / ')}';
      }
      if (msg != null && !bad) {
        bad = true;
        failing.add(s);
        if (first == null) {
          first = msg;
          firstBook = b;
          firstTarget = id;
        }
      }
    }
  }
  final out = StringBuffer(
    '[$name] seeds ${useSeeds.length}, targets tried $tried, '
    'failing seeds ${failing.length} $failing',
  );
  if (first != null) {
    final id = firstTarget!;
    bool fails(List<Entry> es) {
      final ids = {for (final e in es) e.id};
      if (es.any((e) => e.refundOf != null && !ids.contains(e.refundOf))) {
        return false;
      }
      try {
        final l = rebuild(es, recurring: recurring);
        final t = byKey(l, id);
        if (t == null) return false;
        return run(l, t) != null;
      } catch (_) {
        return false;
      }
    }

    var cur = [...firstBook!.log];
    if (fails(cur)) {
      var chunk = cur.length ~/ 2;
      while (chunk >= 1) {
        var i = 0;
        var progressed = false;
        while (i < cur.length) {
          final tryList = [...cur]..removeRange(i, min(i + chunk, cur.length));
          if (tryList.length < cur.length && fails(tryList)) {
            cur = tryList;
            progressed = true;
          } else {
            i += chunk;
          }
        }
        if (!progressed || chunk == 1) chunk ~/= 2;
      }
    }
    out.writeln();
    out.writeln('  first failure (unshrunk, target $id): $first');
    out.writeln(
      '  minimal book (${cur.length} of ${firstBook.log.length}), target $id:',
    );
    for (final e in cur) {
      out.writeln('    ${show(e)}${e.id == id ? '   ' : ''}');
    }
    final l = rebuild(cur, recurring: recurring);
    final t = byKey(l, id);
    out.write(
      '  on the minimal book: ${t == null ? 'target gone' : run(l, t)}',
    );
  }
  // ignore: avoid_print
  print(out);
  return first == null ? null : out.toString();
}

String keyOf(Entry e) =>
    '${show(e)}|${e.recurring}|${e.date.millisecondsSinceEpoch}';
Entry? byKey(Ledger l, String key) {
  for (final e in l.entries.all) {
    if (keyOf(e) == key) return e;
  }
  return null;
}

Map<String, Object?> jsonOf(Entry e) => entryToJson(e);
Entry fromJson(Map<String, Object?> j) => entryFromJson(j);
String enc(Object? o) => jsonEncode(o);

/// [m] without the keys that name a record by a random id (starter
/// accounts get random ids per book).
Map<String, String> stable(Map<String, String> m) => {
  for (final e in m.entries)
    if (!RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-').hasMatch(e.key)) e.key: e.value,
};
