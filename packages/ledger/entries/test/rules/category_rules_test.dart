import 'package:ledger_entries/model.dart';
import 'package:ledger_entries/rules.dart';
import 'package:test/test.dart';

const _parents = {'早餐': '飲食', '咖啡': '早餐', '飲食': null, 'a': 'b', 'b': 'a'};
String? _parentOf(String name) => _parents[name];

Entry _spend(String category, {List<(String, int)> parts = const []}) => Entry(
  id: 'e',
  date: DateTime.utc(2026, 10, 1),
  type: EntryType.expense,
  amount: 100,
  account: 'bank',
  category: category,
  parts: parts,
);

void main() {
  test('under a category: itself and its subcategories, at any depth', () {
    expect(isUnder('飲食', '飲食', _parentOf), isTrue);
    expect(isUnder('早餐', '飲食', _parentOf), isTrue);
    expect(isUnder('咖啡', '飲食', _parentOf), isTrue);
    expect(isUnder('飲食', '早餐', _parentOf), isFalse);
    expect(isUnder('交通', '飲食', _parentOf), isFalse);
  });

  test('a loop of parents ends', () {
    expect(lineOf('a', _parentOf), ['a', 'b']);
    expect(topOf('咖啡', _parentOf), '飲食');
  });

  test('an entry\'s spending under a category counts the parts below it', () {
    final e = _spend('早餐', parts: const [('早餐', 70), ('交通', 30)]);
    expect(spendingUnder(e, '飲食', _parentOf), 70);
    expect(entryIsUnder(e, '飲食', _parentOf), isTrue);
    expect(entryIsUnder(_spend('交通'), '飲食', _parentOf), isFalse);
    // A part in a subcategory of an entry kept under another category.
    final other = _spend('交通', parts: const [('交通', 60), ('咖啡', 40)]);
    expect(entryIsUnder(other, '飲食', _parentOf), isTrue);
    expect(spendingUnder(other, '飲食', _parentOf), 40);
  });

  test('amounts by the category at the top', () {
    expect(byTopCategory({'早餐': 100, '交通': 50, '飲食': 20, '咖啡': 5}, _parentOf), {
      '飲食': 125,
      '交通': 50,
    });
  });
}
