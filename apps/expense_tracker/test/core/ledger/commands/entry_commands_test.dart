import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// R17: putting a deleted entry back from the trash (D78 holds, all or
/// nothing) and which let-go day a restored booking takes back; R20: a
/// restore told once, groups weighed whole, an undo held like the trash.
void main() {
  // R20: a purchase of 300 and its refund on 銀行; g1 on 銀行 and g2 on 舊
  // written as one (group G); a on 銀行 alone.
  Ledger book20({int refund = 100, String refundOn = 'bank'}) => Ledger(
    today: DateTime.utc(2026, 10, 1),
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 1000),
      Account('old', '舊', AccountKind.bank, 1000),
    ],
    categories: const [],
    entries: [
      Entry(
        id: 'buy',
        date: DateTime.utc(2026, 9, 20),
        type: EntryType.expense,
        amount: 300,
        account: 'bank',
      ),
      Entry(
        id: 'ref',
        date: DateTime.utc(2026, 9, 21),
        type: EntryType.income,
        amount: refund,
        account: refundOn,
        refundOf: 'buy',
      ),
      Entry(
        id: 'g1',
        date: DateTime.utc(2026, 9, 22),
        type: EntryType.expense,
        amount: 5,
        account: 'bank',
        group: 'G',
      ),
      Entry(
        id: 'g2',
        date: DateTime.utc(2026, 9, 22),
        type: EntryType.expense,
        amount: 5,
        account: 'old',
        group: 'G',
      ),
      Entry(
        id: 'a',
        date: DateTime.utc(2026, 9, 23),
        type: EntryType.expense,
        amount: 7,
        account: 'bank',
      ),
    ],
    holdings: const [],
    budgets: const [],
    recurring: const [],
  );

  void close(Ledger l, String id) =>
      l.accountCommands.updateAccount(l.account(id).copyWith(archived: true));

  List<String> live(Ledger l) => [for (final e in l.entries.all) e.id];

  List<String> trashed(Ledger l) =>
      [for (final t in l.trash.all) t.entry.id]..sort();

  /// What a listener sees of [l]: the entries, the trash, whether 銀行 is
  /// closed and its balance.
  String seen(Ledger l) =>
      '${live(l)} ${trashed(l)} ${l.account('bank').archived} '
      '${l.balanceService.balance('bank')}';

  group('R20: a restore is one quiet change', () {
    test('restored with its purchase: every listener, and the problem, hear '
        'of it once, at rest', () {
      final ledger = book20();
      ledger.entryCommands.remove('ref');
      ledger.entryCommands.remove('buy');
      close(ledger, 'bank');
      final before = seen(ledger);
      final states = <String>[];
      final watched = <String>[];
      ledger.addListener(() => states.add(seen(ledger)));
      ledger
          .watch(const {Topic.entries})
          .addListener(() => watched.add(seen(ledger)));
      ledger.problem.addListener(() => states.add('problem'));
      final ok = ledger.entryCommands.restoreTrashed(
        ledger.trash.all.firstWhere((t) => t.entry.id == 'ref'),
        reopen: true,
        withOriginal: true,
      );
      expect(ok, isTrue);
      // 1000 - 300 + 100 - 5 - 7.
      const after = '[buy, ref, g1, g2, a] [] false 788';
      expect(before, '[g1, g2, a] [buy, ref] true 988');
      expect(states, [after]);
      expect(watched, [after]);
    });

    test('refused (a refund of 400 for a purchase of 300): the problem and '
        'one change, both after it is all undone', () {
      final ledger = book20(refund: 400);
      ledger.entryCommands.remove('ref');
      ledger.entryCommands.remove('buy');
      close(ledger, 'bank');
      final before = seen(ledger);
      final states = <String>[];
      ledger.addListener(() => states.add(seen(ledger)));
      ledger.problem.addListener(() => states.add('problem ${seen(ledger)}'));
      final ok = ledger.entryCommands.restoreTrashed(
        ledger.trash.all.firstWhere((t) => t.entry.id == 'ref'),
        reopen: true,
        withOriginal: true,
      );
      expect(ok, isFalse);
      expect(seen(ledger), before);
      expect(states, ['problem $before', before]);
    });
  });

  group('R20: what comes back with a group is weighed with it', () {
    test('a group member on a closed account holds the whole group', () {
      final ledger = book20();
      ledger.entryCommands.removeAll(['g1', 'g2']);
      close(ledger, 'old');
      final g1 = ledger.trash.all.firstWhere((t) => t.entry.id == 'g1');
      final holds = ledger.entryCommands.holdsOf(g1);
      expect(holds, [isA<ClosedAccounts>()]);
      expect((holds.single as ClosedAccounts).accounts.map((a) => a.id), [
        'old',
      ]);
      expect(ledger.entryCommands.restoreTrashed(g1), isFalse);
      expect(trashed(ledger), ['g1', 'g2']);
      expect(ledger.entryCommands.restoreTrashed(g1, reopen: true), isTrue);
      expect(ledger.account('old').archived, isFalse);
      expect(trashed(ledger), isEmpty);
    });
  });

  group('R20: an undo puts back only what nothing stands in the way of', () {
    test('a group with a member on a closed account stays in the trash; the '
        'rest comes back, and the page is told how many stayed', () {
      final ledger = book20();
      final removed = ledger.entryCommands.removeAll(['g1', 'g2', 'a']);
      close(ledger, 'old');
      final ok = ledger.entryCommands.restoreAll(removed);
      expect(ok, isFalse);
      expect(live(ledger), ['buy', 'ref', 'a']);
      expect(trashed(ledger), ['g1', 'g2']);
      expect(ledger.account('old').archived, isTrue);
      expect(
        ledger.problem.value,
        isA<StayedInTrash>().having((p) => p.count, 'count', 2),
      );
      // From the trash, one by one, once agreed.
      final g1 = ledger.trash.all.firstWhere((t) => t.entry.id == 'g1');
      expect(ledger.entryCommands.restoreTrashed(g1, reopen: true), isTrue);
      expect(live(ledger), ['buy', 'ref', 'g1', 'g2', 'a']);
    });

    test('a purchase stays with its refund', () {
      // The refund is on 舊, closed; the purchase on 銀行, open.
      final ledger = book20(refundOn: 'old');
      final removed = ledger.entryCommands.removeAll(['buy', 'ref', 'a']);
      close(ledger, 'old');
      expect(ledger.entryCommands.restoreAll(removed), isFalse);
      expect(trashed(ledger), ['buy', 'ref']);
      expect(live(ledger), ['g1', 'g2', 'a']);
      expect((ledger.problem.value! as StayedInTrash).count, 2);
    });

    test('a refund whose purchase is not in the book stays; with its '
        'purchase it comes back', () {
      final ledger = book20();
      ledger.entryCommands.remove('buy');
      final refund = ledger.entryCommands.removeAll(['ref']);
      expect(ledger.entryCommands.restoreAll(refund), isFalse);
      expect(trashed(ledger), ['buy', 'ref']);
      expect((ledger.problem.value! as StayedInTrash).count, 1);

      final again = book20();
      final both = again.entryCommands.removeAll(['buy', 'ref']);
      expect(again.entryCommands.restoreAll(both), isTrue);
      expect(live(again), ['buy', 'ref', 'g1', 'g2', 'a']);
      expect(again.problem.value, isNull);
    });

    test('nothing in the way: all of it is back, nothing said', () {
      final ledger = book20();
      final removed = ledger.entryCommands.removeAll(['g1', 'g2']);
      expect(ledger.entryCommands.restoreAll(removed), isTrue);
      expect(live(ledger), ['buy', 'ref', 'g1', 'g2', 'a']);
      expect(ledger.problem.value, isNull);
    });

    test('the undo of one entry whose account closed meanwhile is refused '
        'the same way', () {
      final ledger = book20();
      final a = ledger.entryCommands.remove('a')!;
      close(ledger, 'bank');
      final states = <String>[];
      ledger.addListener(() => states.add('changed'));
      ledger.problem.addListener(() => states.add('problem'));
      expect(ledger.entryCommands.restore(a), isFalse);
      expect(trashed(ledger), ['a']);
      expect((ledger.problem.value! as StayedInTrash).count, 1);
      expect(states, ['problem']);
    });
  });
  group('D78 restore holds', () {
    // A purchase of 300 and its refund of 100, both deleted, then the
    // account closed.
    Ledger book({bool closed = true, int refund = 100}) {
      final ledger = Ledger(
        today: DateTime.utc(2026, 10, 1),
        accounts: const [Account('bank', '銀行', AccountKind.bank, 1000)],
        categories: const [],
        entries: [
          Entry(
            id: 'buy',
            date: DateTime.utc(2026, 9, 20),
            type: EntryType.expense,
            amount: 300,
            account: 'bank',
          ),
          Entry(
            id: 'ref',
            date: DateTime.utc(2026, 9, 21),
            type: EntryType.income,
            amount: refund,
            account: 'bank',
            refundOf: 'buy',
          ),
        ],
        holdings: const [],
        budgets: const [],
        recurring: const [],
      );
      ledger.entryCommands.remove('ref');
      ledger.entryCommands.remove('buy');
      if (closed) {
        ledger.accountCommands.updateAccount(
          ledger.account('bank').copyWith(archived: true),
        );
      }
      return ledger;
    }

    Trashed refundOf(Ledger l) =>
        l.trash.all.firstWhere((t) => t.entry.id == 'ref');

    test(
      'every hold is worked out first, the purchase before the accounts',
      () {
        final ledger = book();
        final holds = ledger.entryCommands.holdsOf(refundOf(ledger));
        expect(holds, [isA<OriginalInTrash>(), isA<ClosedAccounts>()]);
        // The purchase's accounts are asked about too (here the same one).
        expect((holds[1] as ClosedAccounts).accounts.map((a) => a.id), [
          'bank',
        ]);
      },
    );

    test('with no purchase in the trash: gone for good, then the account', () {
      final ledger = book();
      ledger.entryCommands.discardTrashed(
        ledger.trash.all.where((t) => t.entry.id == 'buy').toList(),
      );
      expect(ledger.entryCommands.holdsOf(refundOf(ledger)), [
        isA<OriginalGone>(),
        isA<ClosedAccounts>(),
      ]);
    });

    test('a hold left unagreed changes nothing, in either order', () {
      for (final (reopen, withOriginal) in [(true, false), (false, true)]) {
        final ledger = book();
        final ok = ledger.entryCommands.restoreTrashed(
          refundOf(ledger),
          reopen: reopen,
          withOriginal: withOriginal,
        );
        expect(ok, isFalse, reason: 'reopen $reopen, original $withOriginal');
        expect(ledger.account('bank').archived, isTrue);
        expect(ledger.entries.all, isEmpty);
        expect(ledger.trash.all.length, 2);
      }
    });

    test('all agreed: the account is reopened, purchase and refund are back '
        'together (one write)', () {
      final ledger = book();
      final ok = ledger.entryCommands.restoreTrashed(
        refundOf(ledger),
        reopen: true,
        withOriginal: true,
      );
      expect(ok, isTrue);
      expect(ledger.account('bank').archived, isFalse);
      expect([for (final e in ledger.entries.all) e.id], ['buy', 'ref']);
      expect(ledger.trash.all, isEmpty);
      // 1000 - 300 + 100.
      expect(ledger.balanceService.balance('bank'), 800);
    });

    test('the refund cannot come back: nothing changes, the account stays '
        'closed', () {
      // A refund of 400 of a purchase of 300 is refused by the write rules.
      final ledger = book(refund: 400);
      final ok = ledger.entryCommands.restoreTrashed(
        refundOf(ledger),
        reopen: true,
        withOriginal: true,
      );
      expect(ok, isFalse);
      expect(ledger.account('bank').archived, isTrue);
      expect(ledger.entries.all, isEmpty);
      expect(ledger.trash.all.length, 2);
    });

    test('a purchase alone needs only its account reopened', () {
      final ledger = book();
      final buy = ledger.trash.all.firstWhere((t) => t.entry.id == 'buy');
      expect(ledger.entryCommands.holdsOf(buy), [isA<ClosedAccounts>()]);
      expect(ledger.entryCommands.restoreTrashed(buy, reopen: true), isTrue);
      expect(ledger.account('bank').archived, isFalse);
      expect([for (final e in ledger.entries.all) e.id], ['buy']);
    });
  });

  group('restoring a recurring booking', () {
    Recurring rent() => Recurring(
      id: 'r',
      name: '房租',
      amount: 100,
      day: 1,
      account: 'bank',
      category: '房租',
      start: DateTime.utc(2026, 1, 1),
    );

    // Ten months booked, today 15 October.
    Ledger book() {
      final item = rent();
      final ledger = Ledger(
        today: DateTime.utc(2026, 10, 15),
        accounts: const [Account('bank', '銀行', AccountKind.bank, 20000)],
        categories: const [],
        entries: const [],
        holdings: const [],
        budgets: const [],
        recurring: [item],
      );
      ledger.recurringCommands.bookDays(item, [
        for (var m = 1; m <= 10; m++) DateTime.utc(2026, m, 1),
      ]);
      return ledger;
    }

    Entry on(Ledger l, int m) => l.entries.all.firstWhere(
      (e) => e.recurring == 'r' && e.date == DateTime.utc(2026, m, 1),
    );

    test('only the day it settled is brought back, never another month '
        'let go on purpose', () {
      final ledger = book();
      expect(
        ledger.recurringService.pendingDate(ledger.recurring.all.single),
        isNull,
      );
      // June is let go for good.
      ledger.entryCommands.remove(on(ledger, 6).id);
      ledger.entryCommands.discardTrashed(
        ledger.trash.all.where((t) => t.entry.date.month == 6).toList(),
      );
      // March deleted, its day brought back and booked anew.
      final march = ledger.entryCommands.remove(on(ledger, 3).id)!;
      ledger.recurringCommands.unskip(
        ledger.recurring.all.single,
        DateTime.utc(2026, 3, 1),
      );
      ledger.recurringCommands.confirm(
        ledger.recurring.all.single,
        day: DateTime.utc(2026, 3, 1),
      );
      expect(ledger.recurring.all.single.skipped, {DateTime.utc(2026, 6, 1)});
      // The old March entry comes back (a second booking of the day).
      ledger.entryCommands.restoreTrashed(
        ledger.trash.all.firstWhere((t) => t.entry.id == march.id),
      );
      expect(ledger.recurring.all.single.skipped, {DateTime.utc(2026, 6, 1)});
      expect(
        ledger.recurringService.pendingDate(ledger.recurring.all.single),
        isNull,
      );
    });

    test('restoring the booking takes back exactly the day it let go', () {
      final ledger = book();
      final march = ledger.entryCommands.remove(on(ledger, 3).id)!;
      ledger.entryCommands.remove(on(ledger, 6).id);
      expect(ledger.recurring.all.single.skipped, {
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 6, 1),
      });
      ledger.entryCommands.restoreTrashed(
        ledger.trash.all.firstWhere((t) => t.entry.id == march.id),
      );
      expect(ledger.recurring.all.single.skipped, {DateTime.utc(2026, 6, 1)});
    });

    test('an undo takes back the day that deletion let go', () {
      final ledger = book();
      final first = ledger.entryCommands.remove(on(ledger, 3).id)!;
      expect(ledger.recurring.all.single.skipped, {DateTime.utc(2026, 3, 1)});
      expect(ledger.entryCommands.restore(first), isTrue);
      expect(ledger.recurring.all.single.skipped, isEmpty);
    });
  });
}
