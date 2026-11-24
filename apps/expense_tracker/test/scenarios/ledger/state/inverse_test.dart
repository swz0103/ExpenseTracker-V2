// Round 6: an operation followed by its inverse restores the exact state
// (every shown number and every record).
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/import_export/model/import_export.dart';
import 'package:expense_tracker/src/features/import_export/ui/import_page.dart'
    show importBookOf;
import 'package:flutter_test/flutter_test.dart';

import '../../../support/state_fingerprint.dart';

/// null when [op] was refused (nothing to compare).
bool attempt(void Function() op) {
  try {
    op();
    return true;
  } catch (_) {
    return false;
  }
}

Entry mutate(Entry e, int variant) {
  final j = Map<String, Object?>.from(jsonOf(e));
  switch (variant % 4) {
    case 0:
      j['amount'] = (j['amount']! as int) + 7;
      if (j['home'] != null) j['home'] = (j['home']! as int) + 7;
    case 1:
      final d = DateTime.parse('${j['date']}')
          .add(Duration(days: variant.isEven ? 3 : -3));
      j['date'] =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    case 2:
      j['account'] = j['account'] == 'bank' ? 'cash' : 'bank';
    default:
      j['tags'] = (j['tags'] as List?)?.isNotEmpty == true
          ? <Object?>[]
          : <Object?>['旅遊'];
  }
  return fromJson(j);
}

void main() {
  test('A1 add -> undo (save with replacing) restores', () {
    final r = inverse('A1 add->undo(save replacing)', (l, t) {
      final n = t.withId(l.newId());
      final s0 = state(l, order: true);
      if (!attempt(() => l.entryCommands.add(n))) return null;
      l.entryCommands.save(const [], replacing: [n.id]);
      return diff(s0, state(l, order: true));
    });
    expect(r, isNull);
  });

  test('A2 add -> remove (as the UI deletes) restores except trash', () {
    final r = inverse('A2 add->remove', (l, t) {
      final n = t.withId(l.newId());
      final s0 = state(l, trash: false, order: true);
      if (!attempt(() => l.entryCommands.add(n))) return null;
      l.entryCommands.remove(n.id);
      return diff(s0, state(l, trash: false, order: true));
    });
    expect(r, isNull);
  });

  test('E1 edit -> undo restores', () {
    final r = inverse('E1 edit->undo', (l, t) {
      final s0 = state(l, order: true);
      final next = mutate(t, t.amount + t.date.day);
      if (!attempt(() => l.entryCommands.replace(next))) return null;
      l.entryCommands.replace(t);
      return diff(s0, state(l, order: true));
    }, targets: 8);
    expect(r, isNull);
  });

  test('D1 delete -> restore (undo) restores records and statistics', () {
    final r = inverse('D1 delete->undo', (l, t) {
      final s0 = state(l);
      final removed = l.entryCommands.remove(t.id);
      if (removed == null) return null;
      if (!l.entryCommands.restore(removed)) {
        return 'restore refused: ${l.problem.value}';
      }
      return diff(s0, state(l));
    }, targets: 10);
    expect(r, isNull);
  });

  test('D1b delete -> undo, tag/merchant lists compared as sets', () {
    listsAsSets = true;
    addTearDown(() => listsAsSets = false);
    final r = inverse('D1b delete->undo (lists as sets)', (l, t) {
      final s0 = state(l);
      final removed = l.entryCommands.remove(t.id);
      if (removed == null) return null;
      if (!l.entryCommands.restore(removed)) {
        return 'restore refused: ${l.problem.value}';
      }
      return diff(s0, state(l));
    }, targets: 10);
    expect(r, isNull);
  });

  test('D3b bulk delete -> undo, lists as sets', () {
    listsAsSets = true;
    addTearDown(() => listsAsSets = false);
    final r = inverse('D3b bulk delete->undo (lists as sets)', (l, t) {
      final all = l.entries.all;
      final i = all.indexWhere((e) => e.id == t.id);
      final ids = [for (var k = i; k < min(i + 4, all.length); k++) all[k].id];
      final s0 = state(l);
      final removed = l.entryCommands.removeAll(ids);
      if (removed.isEmpty) return null;
      if (!l.entryCommands.restoreAll(removed)) return 'restoreAll refused';
      return diff(s0, state(l));
    }, targets: 6);
    expect(r, isNull);
  });

  test('D1o delete -> undo restores the order of entries', () {
    final r = inverse('D1o order after delete->undo', (l, t) {
      final before = [for (final e in l.entries.all) e.id];
      final removed = l.entryCommands.remove(t.id);
      if (removed == null) return null;
      l.entryCommands.restore(removed);
      final after = [for (final e in l.entries.all) e.id];
      final i = before.indexOf(t.id);
      return before.join() == after.join()
          ? null
          : 'entry was at index $i of ${before.length}, after undo at ${after.indexOf(t.id)}';
    }, targets: 3);
    expect(r, isNull);
  });

  test('D2 delete -> trash restore restores', () {
    final r = inverse('D2 delete->trash restore', (l, t) {
      final s0 = state(l);
      if (l.entryCommands.remove(t.id) == null) return null;
      if (l.trash.all.length != 1) return 'trash has ${l.trash.all.length}';
      if (!l.entryCommands.restoreTrashed(l.trash.all.first)) {
        return 'trash restore refused: ${l.problem.value}';
      }
      return diff(s0, state(l));
    }, targets: 10);
    expect(r, isNull);
  });

  test('D3 bulk delete -> undo restores', () {
    final r = inverse('D3 bulk delete->undo', (l, t) {
      final all = l.entries.all;
      final i = all.indexWhere((e) => e.id == t.id);
      final ids = [for (var k = i; k < min(i + 4, all.length); k++) all[k].id];
      final s0 = state(l);
      final removed = l.entryCommands.removeAll(ids);
      if (removed.isEmpty) return null;
      if (!l.entryCommands.restoreAll(removed)) {
        return 'restoreAll refused: ${l.problem.value}';
      }
      return diff(s0, state(l));
    }, targets: 6);
    expect(r, isNull);
  });

  test('C1 category rename -> rename back restores', () {
    final r = inverse(
      'C1 rename category and back',
      (l, t) {
        final name = t.parts.isNotEmpty ? t.parts.first.$1 : t.category;
        if (name.isEmpty || l.categories.all.every((c) => c.name != name)) {
          return null;
        }
        l.budgetCommands.setBudget(name, 1000);
        l.budgetCommands.setBudget('#旅遊', 500);
        // a trashed entry of that category, as the trash follows renames
        final other = l.entries.all.where(
          (e) => e.category == name && e.id != t.id && e.recurring == null,
        );
        if (other.isNotEmpty) l.entryCommands.remove(other.first.id);
        final s0 = state(l);
        final c = l.category(name);
        l.categoryCommands.updateCategory(name, c.copyWith(name: '新名稱'));
        l.categoryCommands.updateCategory(
          '新名稱',
          l.category('新名稱').copyWith(name: name),
        );
        return diff(s0, state(l));
      },
      targets: 6,
      only: (e) => e.type == EntryType.expense,
    );
    expect(r, isNull);
  });

  test('C2 category merge conserves totals (no undo offered)', () {
    final r = inverse(
      'C2 merge conserves spending',
      (l, t) {
        final from = t.category;
        if (from.isEmpty) return null;
        final into = from == '購物' ? '娛樂' : '購物';
        if (!l.categories.all.any((c) => c.name == into) ||
            l.category(from).income) {
          return null;
        }
        final month = [for (var m = 6; m <= 10; m++) m];
        int sum(String k) => [
          for (final m in month)
            l.reportService.spendingBetween(first(m), last(m))[k] ?? 0,
        ].fold(0, (a, b) => a + b);
        final total = sum(from) + sum(into);
        final bal = {
          for (final a in l.accounts.all) a.id: l.balanceService.balance(a.id),
        };
        l.categoryCommands.mergeCategory(from, into);
        final after = sum(into);
        final bal2 = {
          for (final a in l.accounts.all) a.id: l.balanceService.balance(a.id),
        };
        if (bal.toString() != bal2.toString()) {
          return 'balances changed $bal -> $bal2';
        }
        if (sum(from) != 0) return 'source still has ${sum(from)}';
        return total == after
            ? null
            : 'spending of $from+$into $total, after merge $after';
      },
      targets: 4,
      only: (e) => e.type == EntryType.expense && e.parts.isEmpty,
    );
    expect(r, isNull);
  });

  test('R1 recurring: book -> delete booking -> undo equals booked state', () {
    final r = inverse('R1 confirm, delete, undo', (l, t) {
      final item = l.recurring.byId('sub')!;
      if (l.recurringService.pendingDate(item) == null) return null;
      l.recurringCommands.confirm(item);
      final s1 = state(l);
      final booked = l.entries.all.last;
      final removed = l.entryCommands.remove(booked.id)!;
      if (!l.entryCommands.restore(removed)) return 'restore refused';
      return diff(s1, state(l), an: 'booked', bn: 'after delete+undo');
    }, targets: 1);
    expect(r, isNull);
  });

  test('R2 recurring: book -> delete -> 恢復 equals state before booking', () {
    final r = inverse('R2 confirm, delete, unskip = before', (l, t) {
      final item = l.recurring.byId('sub')!;
      final p0 = l.recurringService.pendingDate(item);
      if (p0 == null) return null;
      final s0 = state(l);
      l.recurringCommands.confirm(item);
      final booked = l.entries.all.last;
      l.entryCommands.remove(booked.id);
      final skipped = l.recurring.byId('sub')!.skipped;
      if (skipped.isEmpty) return 'no skipped day after deleting booking';
      for (final d in skipped.toList()) {
        l.recurringCommands.unskip(l.recurring.byId('sub')!, d);
      }
      final s2 = stats(l);
      final want = {for (final e in stats(freshOf(l)).entries) e.key: e.value};
      // Compare pending state with before (entries differ: trash holds the booking)
      final keys = [
        for (final k in s0.keys)
          if (k.startsWith('stat/rec:')) k,
      ];
      final bad = [
        for (final k in keys)
          if (s0[k] != s2[k.substring(5)])
            '$k before ${s0[k]} after ${s2[k.substring(5)]}',
      ];
      if (s2.toString() != want.toString()) {
        return 'cache != fresh after unskip: ${diff({for (final e in want.entries) e.key: e.value}, s2, an: 'fresh', bn: 'cached')}';
      }
      return bad.isEmpty ? null : bad.take(3).join(' | ');
    }, targets: 1);
    expect(r, isNull);
  });

  test('R3 bookDue -> delete all booked -> undo equals booked state', () {
    final r = inverse('R3 bookDue, removeAll, restoreAll', (l, t) {
      // new day: auto items book again
      final adv = DateTime.utc(2026, 12, 6);
      final lx = Ledger(
        today: adv,
        accounts: l.accounts.all,
        categories: l.categories.all,
        entries: l.entries.all,
        holdings: const [],
        budgets: l.budgets.all,
        recurring: l.recurring.all,
        rates: const {'USD': 32.0},
      );
      // More than one day waiting is confirmed first (D61): confirmed.
      final due = lx.recurringCommands.bookDue();
      var n = due.booked;
      for (final h in due.held) {
        n += lx.recurringCommands.bookDays(h.item, h.days);
      }
      if (n == 0) return null;
      final booked = lx.entries.all
          .skip(l.entries.length)
          .map((e) => e.id)
          .toList();
      final s1 = state(lx);
      final removed = lx.entryCommands.removeAll(booked);
      if (!lx.entryCommands.restoreAll(removed)) return 'restoreAll refused';
      return diff(s1, state(lx), an: 'booked', bn: 'after delete+undo');
    }, targets: 1);
    expect(r, isNull);
  });

  test('I1 import -> delete imported restores statistics', () {
    String csvOf(int seed) {
      final other = generate(seed + 500, 60, off: {'trade'}).ledger;
      return toCsv(
        other.accounts,
        other.entries.all,
      ).replaceAll('現金', '新現金').replaceAll('娛樂', '新分類');
    }

    final r = inverse(
      'I1 import->delete imported',
      (l, t) {
        final seed = t.amount;
        final text = csvOf(seed);
        final found = importCsv(importBookOf(l), text, fallback: 'bank');
        if (found.entries.isEmpty) return null;
        final s0 = stats(l);
        final before = Map.of(s0);
        final ids = [for (final e in found.entries) e.id];
        addImport(l.entryCommands, found);
        final removed = l.entryCommands.removeAll(ids);
        if (removed.length != ids.length) {
          return 'removed ${removed.length} of ${ids.length}: ${l.problem.value}';
        }
        final s1 = stats(l);
        final bad = [
          for (final k in before.keys)
            if (!k.startsWith('bal:新') &&
                k != 'catsByUse' &&
                before[k] != s1[k])
              '$k before ${before[k]} after ${s1[k]}',
        ];
        return bad.isEmpty
            ? null
            : '${bad.length} differences, first: ${bad.take(4).join(' | ')}';
      },
      targets: 1,
      recurring: false,
    );
    expect(r, isNull);
  });

  test('I2 imported account/category can be removed again after deleting its entries', () {
    final l = generate(3, 80, off: {'trade'}).ledger;
    final other = generate(503, 60, off: {'trade'}).ledger;
    final text = toCsv(
      other.accounts,
      other.entries.all,
    ).replaceAll('現金', '新現金').replaceAll('娛樂', '新分類');
    final found = importCsv(importBookOf(l), text, fallback: 'bank');
    final newAccounts = found.accounts.map((a) => a.id).toList();
    addImport(l.entryCommands, found);
    final ids = [for (final e in found.entries) e.id];
    l.entryCommands.removeAll(ids);
    for (final id in newAccounts) {
      // Only the trash names it: said, and emptied with it, as the
      // account form does (D78).
      expect(l.accountCommands.usedOutsideTrash(id), isFalse);
      final trashed = l.accountCommands.trashedNaming(id);
      expect(trashed, isNotEmpty);
      l.accountCommands.removeAccount(id);
      expect(l.accounts.byId(id), isNotNull, reason: 'not from under them');
      l.entryCommands.discardTrashed(trashed);
      l.accountCommands.removeAccount(id);
    }
    final left = [
      for (final id in newAccounts)
        if (l.accounts.byId(id) != null) id,
    ];
    // ignore: avoid_print
    print(
      '[I2 import then delete imported entries] new accounts ${newAccounts.length}, '
      'still present after removeAccount: ${left.length} (trash holds ${l.trash.all.length} entries mentioning them)',
    );
    expect(left, isEmpty);
  });

  test('X1 cache coherence: after random op sequences, cached stats == fresh rebuild', () {
    final bad = <String>[];
    for (final s in seeds) {
      final l = book(s);
      final r = Random(s);
      stats(l);
      for (var step = 0; step < 25; step++) {
        final es = l.entries.all;
        if (es.isEmpty) break;
        final e = es[r.nextInt(es.length)];
        switch (r.nextInt(6)) {
          case 0:
            attempt(() => l.entryCommands.replace(mutate(e, r.nextInt(100))));
          case 1:
            final x = l.entryCommands.remove(e.id);
            if (x != null && r.nextBool()) l.entryCommands.restore(x);
          case 2:
            if (l.trash.all.isNotEmpty) {
              l.entryCommands.restoreTrashed(
                l.trash.all[r.nextInt(l.trash.all.length)],
              );
            }
          case 3:
            attempt(() => l.entryCommands.add(e.withId(l.newId())));
          case 4:
            l.entryCommands.renameTag('旅遊', r.nextBool() ? '日常' : '');
          default:
            l.entryCommands.renameMerchant('全家', '7-11');
        }
        if (step % 5 == 4) {
          final d = diff(
            stats(freshOf(l)),
            stats(l),
            an: 'fresh',
            bn: 'cached',
          );
          if (d != null) {
            bad.add('seed $s step $step: $d');
            break;
          }
        }
      }
    }
    // ignore: avoid_print
    print(
      '[X1 cached == fresh rebuild] seeds ${seeds.length}, failing ${bad.length}: ${bad.take(2)}',
    );
    expect(bad, isEmpty);
  });
}
