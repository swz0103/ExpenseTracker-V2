import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/features/categories/model/category_form.dart';
import 'package:flutter_test/flutter_test.dart';

Ledger _book() => Ledger(
  today: DateTime.utc(2026, 10, 4),
  accounts: const [Account('bank', '銀行', AccountKind.bank, 0)],
  categories: [
    Category('居家', 'home', 0xFF5B8DB0),
    Category('房租', 'home', 0xFF5B8DB0, parent: '居家'),
    Category('水電', 'home', 0xFF5B8DB0, parent: '居家', archived: true),
    Category('飲食', 'food', 0xFFD08A5A),
    Category('薪資', 'income', 0xFF5C9A83, income: true),
  ],
  entries: const [],
  holdings: const [],
  budgets: const [],
  recurring: const [],
);

Category _named(Ledger l, String name) =>
    l.categories.all.firstWhere((c) => c.name == name);

void main() {
  test('a kept category at the top offers its open subcategories', () {
    final l = _book();
    final form = CategoryForm(_named(l, '居家'), ledger: l);
    expect([for (final c in form.children) c.name], ['房租']);
    expect(form.offersChildren, isTrue);
    // With subcategories of its own it stays at the top.
    expect(form.parents, ['飲食']);
    expect(form.offersParent, isFalse);
  });

  test('a subcategory may move, but has none of its own', () {
    final l = _book();
    final form = CategoryForm(_named(l, '房租'), ledger: l);
    expect(form.offersChildren, isFalse);
    expect(form.parents, ['居家', '飲食']);
    expect(form.offersParent, isTrue);
  });

  test('a new category is not kept, so it is not merged or archived', () {
    final l = _book();
    final form = CategoryForm(Category('', 'other', 0xFF000000), ledger: l);
    expect(form.isNew, isTrue);
    expect(form.book, isNull);
    expect(form.children, isEmpty);
    expect(form.offersChildren, isFalse);
    // Only those of its own side, at the top, may hold it.
    expect(form.parents, ['居家', '飲食']);
  });

  test('a name taken by another category is refused', () {
    final l = _book();
    final form = CategoryForm(_named(l, '飲食'), ledger: l);
    expect(form.problemOf('居家'), contains('居家'));
    expect(form.problemOf('飲食'), isNull);
    expect(form.problemOf('外食'), isNull);
    // Without a book there is nothing to check against.
    expect(CategoryForm(_named(l, '飲食')).problemOf('居家'), isNull);
  });

  test('the category built keeps what the form does not change', () {
    final l = _book();
    final kept = _named(l, '房租').copyWith(archived: true, place: 7);
    final form = CategoryForm(kept, ledger: l)
      ..icon = 'car'
      ..color = 0xFF112233
      ..parent = null;
    expect(form.build('  '), isNull);
    final made = form.build('  租金 ')!;
    expect(made.name, '租金');
    expect((made.icon, made.color, made.parent), ('car', 0xFF112233, null));
    expect((made.archived, made.place, made.income), (true, 7, false));
  });

  test('a new subcategory takes the icon and the colour chosen', () {
    final l = _book();
    final form = CategoryForm(_named(l, '居家'), ledger: l)..color = 0xFF010203;
    final child = form.newChild;
    expect((child.name, child.icon, child.color), ('', 'home', 0xFF010203));
    expect(child.parent, '居家');
  });
}
