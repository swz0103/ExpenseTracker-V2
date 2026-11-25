// Round 6, more inverses: bulk edits, tag/merchant renames, grouped
// entries, calendar 恢復 of a deleted booking.
import 'dart:math';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/state_fingerprint.dart';

void main() {
  test('BULK1 recategorize / moveToAccount, then put the originals back', () {
    final r = inverse(
      'BULK1 bulk edit then replaceAll(originals)',
      (l, t) {
        final all = l.entries.all;
        final i = all.indexWhere((e) => e.id == t.id);
        final picked = [
          for (var k = i; k < min(i + 6, all.length); k++) all[k],
        ];
        final s0 = state(l, order: true);
        final n1 = l.entryCommands.recategorize(
          picked,
          t.category == '購物' ? '娛樂' : '購物',
        );
        final n2 = l.entryCommands.moveToAccount(
          picked,
          t.account == 'bank' ? 'cash' : 'bank',
        );
        if (n1 + n2 == 0) return null;
        l.entryCommands.replaceAll(picked);
        return diff(s0, state(l, order: true));
      },
      targets: 8,
      only: (e) => e.type == EntryType.expense,
    );
    expect(r, isNull);
  });

  test('TAG1 rename tag to a fresh name and back; merchant too', () {
    final r = inverse('TAG1 rename tag/merchant and back', (l, t) {
      l.budgetCommands.setBudget('#旅遊', 900);
      final victim = l.entries.all.firstWhere(
        (e) => e.merchant.isNotEmpty,
        orElse: () => t,
      );
      l.entryCommands.remove(victim.id); // a trashed entry follows renames too
      final s0 = state(l);
      l.entryCommands.renameTag('旅遊', '新標籤');
      l.entryCommands.renameTag('新標籤', '旅遊');
      l.entryCommands.renameMerchant('全家', '新商家');
      l.entryCommands.renameMerchant('新商家', '全家');
      return diff(s0, state(l));
    }, targets: 3);
    expect(r, isNull);
  });

  test('G1 a spending paid for someone (group): delete -> trash restore, delete all -> undo', () {
    final bad = <String>[];
    for (final s in seeds.take(10)) {
      final l = generate(s, 80).ledger;
      addRecurring(l);
      final g = l.newId();
      final own = entryOf(
        l.newId(),
        day(2026, 10, 20),
        EntryType.expense,
        600,
        'bank',
        category: '飲食',
      ).inGroup(g);
      final lent = entryOf(
        l.newId(),
        day(2026, 10, 20),
        EntryType.transfer,
        400,
        'bank',
        to: 'recv',
        category: '轉帳',
      ).inGroup(g);
      l.entryCommands.save([own, lent]);
      final s0 = state(l);
      // delete one member the way the tile does (the whole group goes)
      final ids = [for (final m in l.entryQueryService.groupOf(own)) m.id];
      final removed = l.entryCommands.removeAll(ids);
      if (removed.length != 2) {
        bad.add('seed $s: group removed ${removed.length}');
      }
      final mid = state(l);
      if (l.trash.all.length != 2) {
        bad.add('seed $s: trash ${l.trash.all.length}');
      }
      // restore ONE from the trash: its group comes with it?
      final ok = l.entryCommands.restoreTrashed(l.trash.all.first);
      final m1 = diff(s0, state(l));
      if (!ok || m1 != null) {
        bad.add('seed $s trash restore of one member: ok=$ok ${m1 ?? ''}');
      }
      // and again via removeAll/restoreAll
      final again = l.entryCommands.removeAll(ids);
      if (!l.entryCommands.restoreAll(again)) {
        bad.add('seed $s: restoreAll refused');
      }
      final m2 = diff(s0, state(l));
      if (m2 != null) bad.add('seed $s restoreAll: $m2');
      if (mid.isEmpty) bad.add('x');
    }
    // ignore: avoid_print
    print(
      '[G1 grouped entries] seeds 10, failing ${bad.length}: ${bad.take(3)}',
    );
    expect(bad, isEmpty);
  });

  test('R4 delete an earlier month\'s booking after a later one exists, 恢復 the day: pending again?', () {
    var now = day(2026, 10, 15);
    final l = ledgerOf(
      today: now,
      clock: () => now,
      accounts: accounts,
      categories: categories,
      recurring: [recurringItems[1]], // sub: day 12, manual
    );
    final item = l.recurring.byId('sub')!;
    final p0 = l.recurringService.pendingDate(item);
    l.recurringCommands.confirm(item); // books 10/12
    now = day(2026, 11, 14);
    l.checkDay();
    final pNov = l.recurringService.pendingDate(l.recurring.byId('sub')!);
    l.recurringCommands.confirm(l.recurring.byId('sub')!); // books 11/12
    final oct = l.entries.all.firstWhere((e) => e.date.month == 10);
    l.entryCommands.remove(oct.id);
    final skipped = l.recurring.byId('sub')!.skipped;
    for (final d in skipped.toList()) {
      l.recurringCommands.unskip(l.recurring.byId('sub')!, d);
    }
    final p1 = l.recurringService.pendingDate(l.recurring.byId('sub')!);
    // ignore: avoid_print
    print(
      '[R4 恢復 an earlier booking] pending before booking Oct: $p0; Nov pending $pNov; after deleting Oct booking and 恢復 $skipped: pending $p1 (want 2026-10-12)',
    );
    expect(p1, DateTime.utc(2026, 10, 12));
  });
}
