import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/repositories/recurring_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Recurring _item(
  String id, {
  int amount = 100,
  String category = '居家',
  String account = 'a',
}) => Recurring(
  id: id,
  name: id,
  amount: amount,
  day: 5,
  account: account,
  category: category,
);

List<String> _ids(RecurringRepository r) => [for (final x in r.all) x.id];

void main() {
  test('an item is found by its id; one not held is null', () {
    final items = RecurringRepository([_item('rent'), _item('phone')]);
    expect(items.byId('phone')!.id, 'phone');
    expect(items.byId('gone'), isNull);
  });

  test('saving puts an item in place of the one with its id, or adds it', () {
    final items = RecurringRepository([_item('rent'), _item('phone')]);
    items.put(_item('rent', amount: 999));
    items.put(_item('gym'));
    expect(_ids(items), ['rent', 'phone', 'gym']);
    expect(items.byId('rent')!.amount, 999);
  });

  test('items no longer held are not brought back by a replacement', () {
    final items = RecurringRepository([_item('rent')]);
    items.replaceExisting([_item('rent', amount: 5), _item('deleted')]);
    expect(_ids(items), ['rent']);
    expect(items.byId('rent')!.amount, 5);
  });

  test('removing gives back what was removed, or null', () {
    final items = RecurringRepository([_item('rent'), _item('phone')]);
    expect(items.remove('rent')!.id, 'rent');
    expect(items.remove('rent'), isNull);
    expect(_ids(items), ['phone']);
  });

  test('a category renamed moves its items, and only those', () {
    final items = RecurringRepository([
      _item('rent', category: '居家'),
      _item('bus', category: '交通'),
    ]);
    items.renameCategory('居家', '住');
    expect(items.byId('rent')!.category, '住');
    expect(items.byId('bus')!.category, '交通');
  });

  test('an account an item uses is mentioned', () {
    final items = RecurringRepository([_item('rent', account: 'bank')]);
    expect(items.mentionsAccount('bank'), isTrue);
    expect(items.mentionsAccount('cash'), isFalse);
  });

  test('the list handed out is a copy that cannot be changed', () {
    final items = RecurringRepository([_item('rent')]);
    final before = items.all;
    items.put(_item('gym'));
    expect(before, hasLength(1));
    expect(() => items.all.add(_item('x')), throwsUnsupportedError);
  });

  test('read again: all of it is put in place', () {
    final items = RecurringRepository([_item('rent')]);
    items.replaceWith([_item('a'), _item('b')]);
    expect(_ids(items), ['a', 'b']);
    items.replaceWith(items.all);
    expect(_ids(items), ['a', 'b']);
  });
}
