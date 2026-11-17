import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/repositories/account_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Account _a(String id, {int opening = 0, bool archived = false, int? place}) =>
    Account(
      id,
      '帳戶$id',
      AccountKind.bank,
      opening,
      archived: archived,
      place: place,
    );

List<String> _ids(Iterable<Account> accounts) => [
  for (final a in accounts) a.id,
];

void main() {
  test('an id the book has no account for reads as none', () {
    final accounts = AccountRepository([_a('a')]);
    expect(accounts.byId('a')?.name, '帳戶a');
    expect(accounts.byId('x'), isNull);
    expect(accounts.contains('a'), isTrue);
    expect(accounts.contains('x'), isFalse);
  });

  test('the open accounts leave out the archived, keeping the order', () {
    final accounts = AccountRepository([
      _a('a'),
      _a('b', archived: true),
      _a('c'),
    ]);
    expect(_ids(accounts.open), ['a', 'c']);
    expect(_ids(accounts.all), ['a', 'b', 'c']);
    expect(accounts.contains('b'), isTrue);
  });

  test('the list handed out cannot change the repository', () {
    final accounts = AccountRepository([_a('a')]);
    expect(() => accounts.all.add(_a('b')), throwsUnsupportedError);
    expect(_ids(accounts.all), ['a']);
  });

  test('the index follows an added account', () {
    final accounts = AccountRepository([_a('a')]);
    expect(accounts.contains('b'), isFalse);
    accounts.add(_a('b'));
    expect(accounts.byId('b')?.id, 'b');
  });

  test('only accounts with an id not yet in the book are added', () {
    final accounts = AccountRepository([_a('a', opening: 5)]);
    final added = accounts.addNew([
      _a('a', opening: 99),
      _a('b'),
      _a('b', opening: 7),
      _a('c'),
    ]);
    expect(_ids(added), ['b', 'c']);
    expect(_ids(accounts.all), ['a', 'b', 'c']);
    expect(accounts.byId('a')?.opening, 5);
    expect(accounts.byId('b')?.opening, 0);
    expect(accounts.addNew([_a('a')]), isEmpty);
  });

  test('a replaced account stands where the old one stood', () {
    final accounts = AccountRepository([_a('a'), _a('b'), _a('c')]);
    final old = accounts.replace(_a('b', opening: 42));
    expect(old?.opening, 0);
    expect(_ids(accounts.all), ['a', 'b', 'c']);
    expect(accounts.byId('b')?.opening, 42);
    expect(accounts.replace(_a('x')), isNull);
    expect(accounts.contains('x'), isFalse);
  });

  test('placing returns only the moved ones', () {
    final accounts = AccountRepository([_a('a', place: 0), _a('b'), _a('c')]);
    final moved = accounts.place(['c', 'a', 'x']);
    expect([for (final a in moved) (a.id, a.place)], [('c', 0), ('a', 1)]);
    expect(accounts.byId('c')?.place, 0);
    expect(accounts.place(['c', 'a']), isEmpty);
  });

  test('a removed account is gone from the list and the index', () {
    final accounts = AccountRepository([_a('a'), _a('b')]);
    expect(accounts.contains('a'), isTrue);
    expect(accounts.remove('a')?.id, 'a');
    expect(accounts.remove('a'), isNull);
    expect(_ids(accounts.all), ['b']);
    expect(accounts.byId('a'), isNull);
  });

  test('replacing everything takes the order given and a fresh index', () {
    final accounts = AccountRepository([_a('a')]);
    expect(accounts.contains('a'), isTrue);
    final given = [_a('c'), _a('b')];
    accounts.replaceWith(given);
    given.clear();
    expect(_ids(accounts.all), ['c', 'b']);
    expect(accounts.contains('a'), isFalse);
  });
}
