import 'package:expense_tracker/src/core/ledger/models/category.dart';
import 'package:expense_tracker/src/core/ledger/persistence/codec/category_refs.dart';
import 'package:flutter_test/flutter_test.dart';

Category _category(String id, String name) =>
    Category(name, 'food', 0xFF000000, id: id);

void main() {
  group('namesToIds', () {
    String? idOf(String name) => const {'飲食': 'a', '交通': 'b'}[name];

    test('names a known category by id, everything else kept', () {
      expect(
        namesToIds('entry', {
          'id': 'e',
          'category': '飲食',
          'mood': 'happy',
          'parts': [
            {'name': '交通', 'amount': 1},
            {'name': '寵物', 'amount': 2},
          ],
        }, idOf),
        {
          'id': 'e',
          'categoryId': 'a',
          'mood': 'happy',
          'parts': [
            {'categoryId': 'b', 'amount': 1},
            {'name': '寵物', 'amount': 2},
          ],
        },
      );
      expect(
        namesToIds('trash', {
          'on': '2026-10-01',
          'entry': {'id': 'e', 'category': '交通'},
        }, idOf),
        {
          'on': '2026-10-01',
          'entry': {'id': 'e', 'categoryId': 'b'},
        },
      );
      expect(namesToIds('category', {'parent': '飲食'}, idOf), {'parentId': 'a'});
      expect(namesToIds('budget', {'category': '交通', 'limit': 9}, idOf), {
        'limit': 9,
        'categoryId': 'b',
      });
    });

    test('is null when nothing is named by a known name', () {
      expect(namesToIds('entry', {'category': '寵物'}, idOf), isNull);
      expect(namesToIds('entry', {'categoryId': 'a'}, idOf), isNull);
      expect(namesToIds('recurring', {'category': 3}, idOf), isNull);
      expect(namesToIds('account', {'category': '飲食'}, idOf), isNull);
      expect(namesToIds('trash', {'entry': 'odd'}, idOf), isNull);
    });
  });

  test('an id and a name find each other', () {
    final refs = CategoryRefs([_category('a', '飲食'), _category('b', '交通')]);
    expect(refs.idOf('飲食'), 'a');
    expect(refs.nameOf('b'), '交通');
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
    expect(refs.nameOf('a'), 'a');
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

  test('refs of no categories name every id as itself', () {
    final refs = CategoryRefs();
    expect(refs.nameOf('anything'), 'anything');
    expect(refs.idOf('name'), isNull);
  });
}
