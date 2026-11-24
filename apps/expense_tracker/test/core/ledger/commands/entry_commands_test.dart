import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// R17: putting a deleted entry back from the trash (D78 holds, all or
/// nothing) and which let-go day a restored booking takes back.
void main() {
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
