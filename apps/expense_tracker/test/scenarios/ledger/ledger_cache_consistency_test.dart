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
    rates: of.marketData.rates,
  );

  String ids(Iterable<Entry> entries) => entries.map((e) => e.id).join(',');

  /// Everything the screens ask a ledger for, as one comparable text.
  List<String> ask(Ledger l) {
    final from = DateTime.utc(2026, 1, 1);
    final to = DateTime.utc(2026, 12, 31);
    return [
      'spending ${l.reportService.spendingBetween(from, to)}',
      'merchantsBetween ${l.reportService.merchantsBetween(from, to)}',
      'tagsBetween ${l.reportService.tagsBetween(from, to)}',
      'merchants ${l.entryQueryService.merchants}',
      'tagStats ${l.reportService.tagStats}',
      'merchantStats ${l.reportService.merchantStats}',
      'usual ${ids(l.entryQueryService.usual())}',
      'usualIncome ${ids(l.entryQueryService.usual(income: true))}',
      'usualTransfers ${ids(l.entryQueryService.usualTransfers())}',
      'search ${ids(l.entryQueryService.search('店'))}',
      'search2 ${ids(l.entryQueryService.search('家用'))}',
      'main ${l.accounts.main}',
      'open ${l.accounts.open.map((a) => a.id)}',
      'assets ${l.balanceService.assets}',
      'netWorth ${l.balanceService.netWorthAt(today)} ${l.balanceService.netWorthAt(DateTime.utc(2026, 8))}',
      'byUseOut ${l.reportService.categoriesByUse(income: false)}',
      'byUseIn ${l.reportService.categoriesByUse(income: true)}',
      for (final a in l.accounts.all) ...[
        'balance ${a.id} ${l.balanceService.balance(a.id)} '
            '${l.balanceService.balance(a.id, until: DateTime.utc(2026, 9, 1))}',
        'weekly ${a.id} ${l.balanceService.weeklyChanges(a.id)}',
      ],
      for (var m = 1; m <= 10; m++) ...[
        'month $m ${l.reportService.income(2026, m)} ${l.reportService.expense(2026, m)} '
            '${l.reportService.dividends(2026, m)} ${ids(l.entries.inMonth(2026, m))}',
        for (final t in tags)
          'tag $t $m ${l.budgetService.spentOnTag(t, 2026, m)}',
      ],
      for (final a in l.accounts.all)
        if (a.kind == AccountKind.card) ...[
          'statement ${a.id} ${l.statementService.statement(a)} '
              '${l.statementService.statementDue(a)} '
              '${ids(l.statementService.unbilled(a))} '
              '${ids(l.statementService.instalmentsOn(a))}',
        ],
      for (final item in l.recurring.all)
        'recurring ${item.id} ${l.recurringService.pendingDate(item)} '
            '${l.recurringService.nextDate(item)} '
            '${l.recurringService.worth(item)}',
      'due ${l.recurringService.due.map((r) => r.id)} '
          '${l.recurringService.upcoming.map((r) => r.id)}',
      'unrated ${l.balanceService.unrated.map((a) => a.id)}',
      'day ${l.reportService.spentOn(today)} ${ids(l.entries.onDay(today))}',
      for (final b in l.budgets.all) ...[
        'budget ${b.category} ${l.budgetService.spentAgainst(b, 2026, 10)} '
            '${l.budgetService.allowance(b, 2026, 10)} ${l.budgetService.forecast(1000, 2026, 10)}',
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
      const card = Account(
        'k',
        '信用卡',
        AccountKind.card,
        0,
        closingDay: 20,
        dueDay: 5,
      );
      const dollars = Account(
        'u',
        '美元',
        AccountKind.bank,
        50000,
        currency: 'USD',
      );
      Recurring item(String id) => Recurring(
        id: id,
        name: id,
        amount: 100 + r.nextInt(900),
        day: 1 + r.nextInt(28),
        account: r.nextBool() ? 'a' : 'u',
        category: names[r.nextInt(names.length)],
      );
      Entry onCard(String id) => Entry(
        id: id,
        date: DateTime.utc(2026, 8 + r.nextInt(3), 1 + r.nextInt(28)),
        type: EntryType.expense,
        amount: 100 + r.nextInt(2000),
        account: 'k',
        category: names[r.nextInt(names.length)],
        installments: r.nextInt(4) == 0 ? 3 : 1,
      );
      final live = Ledger(
        today: today,
        accounts: [...banks, card, dollars],
        categories: [
          for (final (i, n) in names.indexed)
            Category(n, 'food', 0xFF000000 + i),
          Category('薪水', 'salary', 0xFF2F7A65, income: true),
        ],
        entries: [for (var i = 0; i < 12; i++) make(r, 'seed$i', banks)],
        holdings: const [],
        budgets: const [],
        recurring: [item('rent'), item('phone')],
        dataSource: _Nowhere(),
      );
      var serial = 0;
      ask(live);
      for (var step = 0; step < 90; step++) {
        final what = r.nextInt(14);
        final label = 'step $step action $what';
        switch (what) {
          case 0 || 1:
            live.entryCommands.add(make(r, 'n${serial++}', banks));
          case 2 when live.entries.all.isNotEmpty:
            final old = live.entries.all[r.nextInt(live.entries.length)];
            live.entryCommands.replace(make(r, old.id, banks));
          case 3 when live.entries.all.isNotEmpty:
            live.entryCommands.remove(
              live.entries.all[r.nextInt(live.entries.length)].id,
            );
          case 4:
            live.budgetCommands.setBudget(
              names[r.nextInt(names.length)],
              500 + r.nextInt(5000),
            );
          case 5 when live.budgets.all.isNotEmpty:
            live.budgetCommands.removeBudget(live.budgets.all.first.category);
          case 6:
            live.entryCommands.renameTag(
              tags[r.nextInt(tags.length)],
              tags[r.nextInt(tags.length)],
            );
          case 7:
            live.entryCommands.renameMerchant(
              shops[r.nextInt(shops.length)],
              shops[r.nextInt(shops.length)],
            );
          case 8:
            final a = banks[r.nextInt(banks.length)];
            live.accountCommands.updateAccount(
              Account(a.id, '${a.name}*', a.kind, a.opening + r.nextInt(500)),
            );
          case 9:
            live.entryCommands.add(onCard('k${serial++}'));
          case 10:
            final k = live.account('k');
            live.accountCommands.updateAccount(
              k.copyWith(closingDay: 1 + r.nextInt(28)),
            );
          case 11:
            live.recurringCommands.saveRecurring(
              item(r.nextBool() ? 'rent' : 'phone'),
            );
          case 12:
            live.recurringCommands.confirm(
              live.recurring.all[r.nextInt(live.recurring.all.length)],
            );
          case 13:
            live.holdingCommands.setMarket(
              holdings: const [],
              moves: const {},
              rates: r.nextBool() ? {'USD': 30.0 + r.nextInt(3)} : const {},
            );
        }
        expect(ask(live), ask(fresh(live)), reason: label);
      }
      await live.settled;
    });
  }
}
