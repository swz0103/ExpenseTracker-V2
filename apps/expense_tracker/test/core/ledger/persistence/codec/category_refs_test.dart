import 'package:expense_tracker/src/core/ledger/models/category.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/category_refs.dart';
import 'package:flutter_test/flutter_test.dart';

Category _category(String id, String name) =>
    Category(name, 'food', 0xFF000000, id: id);

void main() {
  test('an id and a name find each other', () {
    final refs = CategoryRefs([_category('a', '飲食'), _category('b', '交通')]);
    expect(refs.idOf('飲食'), 'a');
    expect(refs.nameOf('b'), '交通');
    expect(refs.knows('a'), isTrue);
    expect(refs.knows('z'), isFalse);
  });

  test(
    'a name no category has gives no id, and an id none has gives itself',
    () {
      final refs = CategoryRefs([_category('a', '飲食')]);
      expect(refs.idOf('已刪除'), isNull);
      expect(refs.nameOf('gone-id'), 'gone-id');
    },
  );

  test('renaming a category moves its name, not its id', () {
    final refs = CategoryRefs([_category('a', '飲食')]);
    refs.set(_category('a', '吃飯'));
    expect(refs.nameOf('a'), '吃飯');
    expect(refs.idOf('吃飯'), 'a');
    expect(refs.idOf('飲食'), isNull);
  });

  test('a category taken out is no longer found', () {
    final refs = CategoryRefs([_category('a', '飲食')]);
    refs.remove('a');
    expect(refs.idOf('飲食'), isNull);
    expect(refs.knows('a'), isFalse);
    refs.remove('a'); // twice is fine
  });

  test('two categories swapping names do not lose each other', () {
    final refs = CategoryRefs([_category('a', 'X'), _category('b', 'Y')]);
    refs.set(_category('a', 'Z'));
    refs.set(_category('b', 'X'));
    refs.set(_category('a', 'Y'));
    expect(refs.idOf('X'), 'b');
    expect(refs.idOf('Y'), 'a');
    expect(refs.idOf('Z'), isNull);
  });

  test('lenient refs know every id and name it as itself', () {
    final refs = CategoryRefs.lenient();
    expect(refs.knows('anything'), isTrue);
    expect(refs.nameOf('anything'), 'anything');
    expect(refs.idOf('name'), isNull);
  });
}
