import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/repositories/trash_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Trashed _trashed(
  String id, {
  String account = 'a',
  String? to,
  String note = '',
}) => Trashed(
  Entry(
    id: id,
    date: DateTime.utc(2026, 10, 1),
    type: to == null ? EntryType.expense : EntryType.transfer,
    amount: 100,
    account: account,
    to: to,
    note: note,
  ),
  DateTime.utc(2026, 10, 4),
);

List<String> _ids(TrashRepository t) => [for (final x in t.all) x.entry.id];

void main() {
  test('the last deleted comes first', () {
    final trash = TrashRepository();
    trash.put(_trashed('a'));
    trash.put(_trashed('b'));
    expect(_ids(trash), ['b', 'a']);
  });

  test('several deleted at once: the last of them first, before the older', () {
    final trash = TrashRepository([_trashed('old')]);
    trash.putAll([_trashed('x'), _trashed('y'), _trashed('z')]);
    expect(_ids(trash), ['z', 'y', 'x', 'old']);
  });

  test('entries put back by id leave the trash', () {
    final trash = TrashRepository([
      _trashed('a'),
      _trashed('b'),
      _trashed('c'),
    ]);
    trash.removeEntries({'a', 'c', 'not-there'});
    expect(_ids(trash), ['b']);
  });

  test('the very ones held are taken away, not others with equal ids', () {
    final kept = _trashed('a');
    final trash = TrashRepository([kept, _trashed('b')]);
    trash.removeAll([_trashed('a')]); // another object with the same id
    expect(_ids(trash), ['a', 'b']);
    trash.removeAll([kept]);
    expect(_ids(trash), ['b']);
  });

  test('a change to the deleted entries keeps when each was deleted', () {
    final trash = TrashRepository([_trashed('a'), _trashed('b')]);
    trash.changeEntries(
      (e) => e.id == 'a' ? e.withLabels(merchant: 'changed') : null,
    );
    expect(trash.all.first.entry.merchant, 'changed');
    expect(trash.all.first.on, DateTime.utc(2026, 10, 4));
    expect(trash.all.last.entry.merchant, '');
  });

  test('an account a deleted entry still names is mentioned', () {
    final trash = TrashRepository([_trashed('a', account: 'cash', to: 'bank')]);
    expect(trash.mentionsAccount('cash'), isTrue);
    expect(trash.mentionsAccount('bank'), isTrue);
    expect(trash.mentionsAccount('card'), isFalse);
  });

  test('the list handed out is a copy that cannot be changed', () {
    final trash = TrashRepository([_trashed('a')]);
    final before = trash.all;
    trash.put(_trashed('b'));
    expect(before, hasLength(1));
    expect(() => trash.all.add(_trashed('c')), throwsUnsupportedError);
  });

  test('read again, or undone: all of it is put in place', () {
    final trash = TrashRepository([_trashed('a')]);
    final before = trash.all;
    trash.put(_trashed('b'));
    trash.replaceWith(before);
    expect(_ids(trash), ['a']);
    trash.replaceWith(trash.all);
    expect(_ids(trash), ['a']);
  });
}
