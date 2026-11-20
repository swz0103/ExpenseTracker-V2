import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/ledger/repositories/category_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Category _c(
  String name, {
  String? id,
  int? place,
  String? parent,
  bool income = false,
  bool archived = false,
}) => Category(
  name,
  'other',
  0xFF000000,
  id: id ?? 'id-$name',
  place: place,
  parent: parent,
  income: income,
  archived: archived,
);

List<String> _names(CategoryRepository r) => [for (final c in r.all) c.name];

void main() {
  test('the placed categories come first by place, the others in order', () {
    final categories = CategoryRepository([
      _c('甲'),
      _c('乙', place: 1),
      _c('丙'),
      _c('丁', place: 0),
    ]);
    expect(_names(categories), ['丁', '乙', '甲', '丙']);
  });

  test('a name the book has no category for reads as an unknown one', () {
    final categories = CategoryRepository([_c('飲食')]);
    expect(categories.byName('飲食').id, 'id-飲食');
    final unknown = categories.byName('已刪除');
    expect((unknown.name, unknown.id), ('已刪除', ''));
  });

  test('the list handed out cannot change the repository', () {
    final categories = CategoryRepository([_c('飲食')]);
    expect(() => categories.all.add(_c('交通')), throwsUnsupportedError);
    expect(_names(categories), ['飲食']);
  });

  test('new entries are offered the open categories of their kind', () {
    final categories = CategoryRepository([
      _c('飲食'),
      _c('舊的', archived: true),
      _c('薪水', income: true),
    ]);
    expect(
      [for (final c in categories.forEntries(income: false)) c.name],
      ['飲食'],
    );
    expect(
      [for (final c in categories.forEntries(income: true)) c.name],
      ['薪水'],
    );
  });

  test('a name kept by the book or already taken is not free', () {
    final categories = CategoryRepository([_c('飲食')]);
    for (final name in ['', '  ', allSpending, transferCategory, '#家用']) {
      expect(categories.isNameFree(name), isFalse, reason: name);
    }
    expect(categories.isNameFree('飲食'), isFalse);
    expect(categories.isNameFree(' 飲食 '), isFalse);
    expect(categories.isNameFree('飲食', except: '飲食'), isTrue);
    expect(categories.isNameFree('交通'), isTrue);
  });

  test('the index follows an added category', () {
    final categories = CategoryRepository([_c('飲食')]);
    expect(categories.byName('交通').id, '');
    categories.add(_c('交通'));
    expect(categories.byName('交通').id, 'id-交通');
    categories.addAll([_c('娛樂'), _c('居家')]);
    expect(_names(categories), ['飲食', '交通', '娛樂', '居家']);
    expect(categories.byName('居家').id, 'id-居家');
  });

  test('placing returns only the moved ones and reorders the rest', () {
    final categories = CategoryRepository([
      _c('甲', place: 0),
      _c('乙'),
      _c('丙'),
    ]);
    final moved = categories.place(['丙', '甲', '不存在']);
    expect([for (final c in moved) (c.name, c.place)], [('丙', 0), ('甲', 1)]);
    expect(_names(categories), ['丙', '甲', '乙']);
    expect(categories.place(['丙', '甲']), isEmpty);
  });

  test('a replaced category keeps its id and, when given none, its place', () {
    final categories = CategoryRepository([_c('飲食', place: 3)]);
    final kept = categories.replace('飲食', _c('飲食', id: 'other'))!;
    expect((kept.id, kept.place), ('id-飲食', 3));
    expect(categories.byName('飲食').id, 'id-飲食');
    final moved = categories.replace('飲食', _c('飲食', place: 0))!;
    expect(moved.place, 0);
    expect(categories.replace('不存在', _c('不存在')), isNull);
  });

  test('a rename reaches the category and those under it', () {
    final categories = CategoryRepository([
      _c('飲食'),
      _c('早餐', parent: '飲食'),
      _c('交通'),
    ]);
    categories.rename('飲食', '吃飯');
    expect(_names(categories), ['吃飯', '早餐', '交通']);
    expect(categories.byName('早餐').parent, '吃飯');
    expect(categories.byName('吃飯').id, 'id-飲食');
    expect(categories.byName('飲食').id, '');
  });

  test('a merged category is gone and those under it stand alone', () {
    final categories = CategoryRepository([
      _c('飲食'),
      _c('早餐', parent: '飲食'),
      _c('交通'),
    ]);
    categories.removeMerged('飲食');
    expect(_names(categories), ['早餐', '交通']);
    expect(categories.byName('早餐').parent, isNull);
    expect(categories.byName('飲食').id, '');
  });

  test('replacing everything takes the order given and a fresh index', () {
    final categories = CategoryRepository([_c('飲食')]);
    expect(categories.byName('飲食').id, 'id-飲食');
    final given = [_c('乙'), _c('甲')];
    categories.replaceWith(given);
    given.clear();
    expect(_names(categories), ['乙', '甲']);
    expect(categories.byName('飲食').id, '');
  });
}
