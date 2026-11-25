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
}
