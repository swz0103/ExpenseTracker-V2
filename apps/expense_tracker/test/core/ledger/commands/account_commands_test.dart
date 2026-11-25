import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../baseline/baseline_ledger.dart';

/// D82: an account deleted or archived is told with 復原, which sets it
/// back as it was.
void main() {
  Ledger book() => ledgerOf(
    today: day(2026, 10, 4),
    accounts: const [
      Account('bank', '銀行', AccountKind.bank, 0),
      Account('spare', '備用金', AccountKind.cash, 0),
      Account('cash', '現金', AccountKind.cash, 0),
    ],
    entries: [entryOf('x', day(2026, 10, 1), EntryType.expense, 50, 'bank')],
  );

  List<String> ids(Ledger l) => [for (final a in l.accounts.all) a.id];

  test('a deleted account comes back where it stood', () {
    final l = book();
    final undo = l.accountCommands.removeAccount('spare')!;
    expect(ids(l), ['bank', 'cash']);
    undo();
    expect(ids(l), ['bank', 'spare', 'cash']);
    // Run again, it adds no second one.
    undo();
    expect(ids(l), ['bank', 'spare', 'cash']);
  });

  test('one in use, or none, is not deleted and gives no undo', () {
    final l = book();
    expect(l.accountCommands.removeAccount('bank'), isNull);
    expect(l.accountCommands.removeAccount('none'), isNull);
    expect(ids(l), ['bank', 'spare', 'cash']);
  });

  test('archiving gives an undo that brings it back; again, nothing', () {
    final l = book();
    final undo = l.accountCommands.setArchived('bank', archived: true)!;
    expect(l.account('bank').archived, isTrue);
    expect(l.accountCommands.setArchived('bank', archived: true), isNull);
    expect(l.accountCommands.setArchived('none', archived: true), isNull);
    undo();
    expect(l.account('bank').archived, isFalse);
    // Brought back by hand since: the undo leaves it.
    final again = l.accountCommands.setArchived('bank', archived: true)!;
    l.accountCommands.setArchived('bank', archived: false);
    again();
    expect(l.account('bank').archived, isFalse);
  });

  group('DEB-01: a person who still owes money', () {
    Ledger lent() => ledgerOf(
      today: day(2026, 10, 4),
      accounts: const [
        Account('bank', '銀行', AccountKind.bank, 100000),
        Account('ann', '阿安', AccountKind.receivable, 0),
      ],
      entries: [
        entryOf(
          'lend',
          day(2026, 10, 1),
          EntryType.transfer,
          5000,
          'bank',
          to: 'ann',
        ),
      ],
    );

    test('is not archived, and stays in sight', () {
      final l = lent();
      expect(
        () => l.accountCommands.setArchived('ann', archived: true),
        throwsA(
          isA<RecordRefused>().having((r) => r.issues, 'issues', [
            isA<ArchivedOwing>(),
          ]),
        ),
      );
      expect(l.account('ann').archived, isFalse);
      // A bank account keeps its balance archived.
      expect(l.accountCommands.setArchived('bank', archived: true), isNotNull);
    });

    test('paid back, is archived; brought back and owing again, the undo '
        'of bringing them back leaves them in sight', () {
      final l = lent();
      l.entryCommands.add(
        entryOf(
          'back',
          day(2026, 10, 2),
          EntryType.transfer,
          5000,
          'ann',
          to: 'bank',
        ),
      );
      expect(l.accountCommands.setArchived('ann', archived: true), isNotNull);
      expect(l.account('ann').archived, isTrue);
      final undo = l.accountCommands.setArchived('ann', archived: false)!;
      l.entryCommands.add(
        entryOf(
          'again',
          day(2026, 10, 3),
          EntryType.transfer,
          300,
          'bank',
          to: 'ann',
        ),
      );
      undo();
      expect(l.account('ann').archived, isFalse);
    });

    test('lent money on a day still to come, is not archived; settled '
        'today, is', () {
      final l = ledgerOf(
        today: day(2026, 10, 4),
        accounts: const [
          Account('bank', '銀行', AccountKind.bank, 100000),
          Account('ann', '阿安', AccountKind.receivable, 0),
        ],
        entries: [
          // Six days ahead: nothing owed today, 5000 from 2026-10-10.
          entryOf(
            'lend',
            day(2026, 10, 10),
            EntryType.transfer,
            5000,
            'bank',
            to: 'ann',
          ),
        ],
      );
      expect(l.balanceService.balance('ann'), 0);
      expect(l.balanceService.finalBalance('ann'), 5000);
      expect(
        () => l.accountCommands.setArchived('ann', archived: true),
        throwsA(
          isA<RecordRefused>().having((r) => r.issues, 'issues', [
            isA<ArchivedOwing>(),
          ]),
        ),
      );
      expect(l.account('ann').archived, isFalse);
      // Paid back today: 5000 - 5000 = 0 once the lend's day has come.
      l.entryCommands.add(
        entryOf(
          'back',
          day(2026, 10, 4),
          EntryType.transfer,
          5000,
          'ann',
          to: 'bank',
        ),
      );
      expect(l.accountCommands.setArchived('ann', archived: true), isNotNull);
    });
  });
}
