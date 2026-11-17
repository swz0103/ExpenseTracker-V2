import 'dart:math';

import 'package:expense_tracker/src/core/ledger/persistence/ledger_data_source.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps nothing; the ledger under test only has to accept its batches.
final class _Nowhere implements LedgerDataSource {
  @override
  Future<void> keep(WriteBatch batch) async {}

  @override
  Future<Ledger> load() => throw UnimplementedError();
}

/// A ledger kept warm across many changes must answer exactly as one built
/// fresh from the same records: a cached sum that a change forgot to throw
/// away shows as a difference here. Every query the screens ask repeatedly
/// is compared after every random change.
void main() {
  final today = DateTime.utc(2026, 10, 4);
  const names = ['飲食', '交通', '居家', '娛樂'];
  const shops = ['便當店', '捷運', '房東', '電影院', '咖啡'];
  const tags = ['家用', '旅行', '禮物'];

  Ledger fresh(Ledger of) => Ledger(
    today: today,
    accounts: of.accounts.all,
    categories: of.categories.all,
    entries: of.entries.all,
    holdings: const [],
    budgets: of.budgets.all,
    recurring: of.recurring.all,
  );

  String ids(Iterable<Entry> entries) => entries.map((e) => e.id).join(',');

  /// Everything the screens ask a ledger for, as one comparable text.
  List<String> ask(Ledger l) {
    final from = DateTime.utc(2026, 1, 1);
    final to = DateTime.utc(2026, 12, 31);
    return [
      'spending ${l.spendingBetween(from, to)}',
      'merchantsBetween ${l.merchantsBetween(from, to)}',
      'tagsBetween ${l.tagsBetween(from, to)}',
      'merchants ${l.merchants}',
      'tagStats ${l.tagStats}',
      'merchantStats ${l.merchantStats}',
      'usual ${ids(l.usual())}',
      'usualIncome ${ids(l.usual(income: true))}',
      'usualTransfers ${ids(l.usualTransfers())}',
      'search ${ids(l.search('店'))}',
      'search2 ${ids(l.search('家用'))}',
      'main ${l.accounts.main}',
      'open ${l.accounts.open.map((a) => a.id)}',
      'assets ${l.assets}',
      'netWorth ${l.netWorthAt(today)} ${l.netWorthAt(DateTime.utc(2026, 8))}',
      'byUseOut ${l.categoriesByUse(income: false)}',
      'byUseIn ${l.categoriesByUse(income: true)}',
      for (final a in l.accounts.all) ...[
        'balance ${a.id} ${l.balance(a.id)} '
            '${l.balance(a.id, until: DateTime.utc(2026, 9, 1))}',
        'weekly ${a.id} ${l.weeklyChanges(a.id)}',
      ],
      for (var m = 1; m <= 10; m++) ...[
        'month $m ${l.income(2026, m)} ${l.expense(2026, m)} '
            '${l.dividends(2026, m)} ${ids(l.entries.inMonth(2026, m))}',
        for (final t in tags) 'tag $t $m ${l.spentOnTag(t, 2026, m)}',
      ],
      'day ${l.spentOn(today)} ${ids(l.entries.onDay(today))}',
      for (final b in l.budgets.all) ...[
        'budget ${b.category} ${l.spentAgainst(b, 2026, 10)} '
            '${l.allowance(b, 2026, 10)} ${l.forecast(1000, 2026, 10)}',
      ],
    ];
  }

  Entry make(Random r, String id, List<Account> banks) {
    final kind = r.nextInt(5);
    final from = banks[r.nextInt(banks.length)].id;
    final to = banks[r.nextInt(banks.length)].id;
    final type = kind == 0
        ? EntryType.income
        : kind == 1 && from != to
        ? EntryType.transfer
        : EntryType.expense;
    return Entry(
      id: id,
      date: DateTime.utc(2026, 1 + r.nextInt(10), 1 + r.nextInt(28)),
      type: type,
      amount: 50 + r.nextInt(3000),
      account: from,
      to: type == EntryType.transfer ? to : null,
      category: type == EntryType.transfer
          ? ''
          : names[r.nextInt(names.length)],
      merchant: shops[r.nextInt(shops.length)],
      tags: [if (r.nextBool()) tags[r.nextInt(tags.length)]],
    );
  }

  for (final seed in [1, 7, 42, 2026]) {
    test('a warm ledger answers like a fresh one (seed $seed)', () async {
      final r = Random(seed);
      final banks = [
        const Account('a', '銀行甲', AccountKind.bank, 100000),
        const Account('b', '現金', AccountKind.cash, 5000),
        const Account('c', '銀行乙', AccountKind.bank, 20000),
      ];
      final live = Ledger(
        today: today,
        accounts: banks,
        categories: [
          for (final (i, n) in names.indexed)
            Category(n, 'food', 0xFF000000 + i),
          Category('薪水', 'salary', 0xFF2F7A65, income: true),
        ],
        entries: [for (var i = 0; i < 12; i++) make(r, 'seed$i', banks)],
        holdings: const [],
        budgets: const [],
        recurring: const [],
        dataSource: _Nowhere(),
      );
      var serial = 0;
      ask(live);
      for (var step = 0; step < 60; step++) {
        final what = r.nextInt(9);
        final label = 'step $step action $what';
        switch (what) {
          case 0 || 1:
            live.add(make(r, 'n${serial++}', banks));
          case 2 when live.entries.all.isNotEmpty:
            final old = live.entries.all[r.nextInt(live.entries.length)];
            live.replace(make(r, old.id, banks));
          case 3 when live.entries.all.isNotEmpty:
            live.remove(live.entries.all[r.nextInt(live.entries.length)].id);
          case 4:
            live.setBudget(
              names[r.nextInt(names.length)],
              500 + r.nextInt(5000),
            );
          case 5 when live.budgets.all.isNotEmpty:
            live.removeBudget(live.budgets.all.first.category);
          case 6:
            live.renameTag(
              tags[r.nextInt(tags.length)],
              tags[r.nextInt(tags.length)],
            );
          case 7:
            live.renameMerchant(
              shops[r.nextInt(shops.length)],
              shops[r.nextInt(shops.length)],
            );
          case 8:
            final a = banks[r.nextInt(banks.length)];
            live.updateAccount(
              Account(a.id, '${a.name}*', a.kind, a.opening + r.nextInt(500)),
            );
        }
        expect(ask(live), ask(fresh(live)), reason: label);
      }
      await live.settled;
    });
  }
}
