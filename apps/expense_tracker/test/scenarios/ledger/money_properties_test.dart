// Invariants over the money figures the screens show, on seeded random
// books (review round 5's O2, O2b, K1, C1, C2 and B3, kept): one net
// worth (D63), the credit a card has taken (D67), a category with its
// subcategories (D54), a refund that mirrors its purchase (D65), a
// month-end forecast never below nothing (D64).
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/accounts/model/card_summary.dart';
import 'package:expense_tracker/src/features/entries/ui/entries_filter_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../baseline/baseline_ledger.dart';
import '../../support/seeded_book.dart';

const _seeds = [1, 2, 3, 4, 5, 6, 7, 8];

void expectHolds(String? failure) =>
    expect(failure, isNull, reason: failure ?? '');

void main() {
  setUp(() => startBudgets = const []);

  test('O2: the accounts page\'s net worth is netWorthAt(today), with a '
      'card in credit too', () {
    expectHolds(
      property('O2', (l) {
        final worth = l.balanceService.netWorth(l.today);
        final at = l.balanceService.netWorthAt(l.today);
        if (worth.net != at) return 'page ${worth.net} != netWorthAt $at';
        return null;
      }, seeds: _seeds),
    );
    final l = replay([
      entryOf(
        'a',
        day(2026, 9, 1),
        EntryType.expense,
        500,
        'card',
        category: '購物',
      ),
      entryOf(
        'b',
        day(2026, 9, 2),
        EntryType.transfer,
        1500,
        'bank',
        category: transferCategory,
        to: 'card',
      ),
    ]);
    // The card is 1000 in credit: held, not dropped.
    expect(l.balanceService.balance('card'), 1000);
    expect(
      l.balanceService.netWorth(l.today).net,
      l.balanceService.netWorthAt(l.today),
    );
  });

  test('K1: a card\'s debt + still to bill is what was bought on it, on '
      'every day from its last entry on', () {
    final failures = <String>[];
    for (final seed in _seeds) {
      final g = generate(
        seed,
        120,
        off: {'transfer', 'refund', 'trade', 'usd'},
      );
      var now = day(2026, 12, 31);
      final l = replay(g.log, clock: () => now);
      var bought = 0;
      var last = day(2026, 6, 1);
      for (final e in g.log) {
        if (e.date.isAfter(last)) last = e.date;
        if (e.account == 'card' && e.type == EntryType.expense) {
          bought += e.amount;
        }
      }
      for (
        var d = last;
        !d.isAfter(day(2026, 12, 31));
        d = d.add(const Duration(days: 1))
      ) {
        now = d;
        final s = CardSummary.of(
          l.account('card'),
          statements: l.statementService,
          balances: l.balanceService,
          entries: l.entries,
          accounts: l.accounts,
          today: d,
        );
        if (s.debt + s.pending != bought) {
          failures.add(
            'seed $seed ${d.month}/${d.day}: '
            '${s.debt} + ${s.pending} != $bought',
          );
          break;
        }
      }
    }
    expect(failures, isEmpty);
  });

  test('C1: a parent category\'s budget, list and family agree', () {
    startBudgets = const [Budget('飲食', 8000)];
    expectHolds(
      property('C1', (l) {
        for (final m in [6, 7, 8, 9, 10]) {
          final cats = l.reportService.spendingBetween(
            day(2026, m, 1),
            day(2026, m + 1, 0),
          );
          final family =
              (cats['飲食'] ?? 0) + (cats['早餐'] ?? 0) + (cats['宵夜'] ?? 0);
          const filter = EntryFilter(category: '飲食');
          var listed = 0;
          for (final e in l.entries.inMonth(2026, m)) {
            if (!filter.shows(l, e)) continue;
            for (final (n, v) in e.spendingParts) {
              if (n == '飲食' || n == '早餐' || n == '宵夜') listed += v;
            }
          }
          final spent = l.budgetService.spentAgainst(
            l.budgets.forCategory('飲食'),
            2026,
            m,
          );
          if (listed != family || spent != family) {
            return '$m: family $family, list $listed, budget $spent';
          }
        }
        return null;
      }, seeds: _seeds),
    );
  });

  test('C2: purchases refunded in full leave no category and no tag '
      'behind', () {
    expectHolds(
      property(
        'C2',
        (l) {
          final left = <String, int>{};
          for (final o in l.entries.all) {
            if (o.type != EntryType.expense || o.installments > 1) continue;
            if (l.entryQueryService.refundable(o) != 0) continue;
            // Refunded in full: its parts and its refunds' come to nothing,
            // category by category, and each refund carries its tags.
            for (final (n, v) in o.spendingParts) {
              left[n] = (left[n] ?? 0) + v;
            }
            for (final r in l.entries.refundsOf(o.id)) {
              if (!o.tags.every(r.tags.contains)) {
                return '${r.id}: tags ${r.tags}, purchase ${o.tags}';
              }
              for (final (n, v) in r.spendingParts) {
                left[n] = (left[n] ?? 0) + v;
              }
            }
          }
          left.removeWhere((_, v) => v == 0);
          return left.isEmpty ? null : 'left behind $left';
        },
        seeds: _seeds,
        off: {'usd'},
      ),
    );
  });

  test('B3: the month-end forecast is never below nothing', () {
    expectHolds(
      property('B3', (l) {
        for (final today in [day(2026, 10, 9), day(2026, 10, 20)]) {
          final b = replay(l.entries.all.toList(), today: today);
          final spent = b.reportService.expense(2026, 10);
          final f = b.budgetService.forecast(spent, 2026, 10);
          if (f < 0) return '${today.day}: forecast $f for $spent';
        }
        return null;
      }, seeds: _seeds),
    );
    final l = replay([
      entryOf(
        'a',
        day(2026, 9, 20),
        EntryType.expense,
        3000,
        'bank',
        category: '購物',
      ),
      entryOf(
        'b',
        day(2026, 10, 3),
        EntryType.income,
        3000,
        'bank',
        category: '購物',
        refundOf: 'a',
      ),
    ], today: day(2026, 10, 20));
    expect(
      l.budgetService.forecast(l.reportService.expense(2026, 10), 2026, 10),
      0,
    );
  });
}
