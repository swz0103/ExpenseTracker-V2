import 'package:core/constants/category_colors.dart';
import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/models/models.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// Name, mark, colour and income of [c].
(String, String, int, bool) _look(Category c) =>
    (c.name, c.icon, c.color, c.income);

void main() {
  test('a new book starts with nine categories, six spent and three '
      'earned', () {
    expect(starterCategories().map(_look), [
      ('居家生活', 'home', 0xFF5C9A83, false),
      ('飲食日常', 'food', 0xFFD08B5B, false),
      ('交通通勤', 'travel', 0xFF5B8DB0, false),
      ('購物休閒', 'bag', 0xFF8E7CC0, false),
      ('訂閱服務', 'subscription', 0xFFC9A34A, false),
      ('其他支出', 'other', 0xFFB07A8C, false),
      ('薪資收入', 'salary', 0xFF2F7A65, true),
      ('股息收入', 'dividend', 0xFF5A6FA8, true),
      ('其他收入', 'income', 0xFF4E8A9A, true),
    ]);
  });

  test('new categories take the colours in turn, from the one list', () {
    expect(categoryColorValues, hasLength(12));
    expect(nextCategoryColor(0), 0xFF5B8DB0);
    expect(nextCategoryColor(1), 0xFFD08B5B);
    expect(nextCategoryColor(11), 0xFFB08AA6);
    // 12 % 12 = 0 and 25 % 12 = 1: round again after the last.
    expect(nextCategoryColor(12), 0xFF5B8DB0);
    expect(nextCategoryColor(25), 0xFFD08B5B);
    // The screens offer the same colours, in the same order.
    expect(
      [for (final c in AppColors.categoryColors) c.toARGB32()],
      [for (final v in categoryColorValues) v],
    );
  });

  test('each call gives categories ids of their own', () {
    final once = {for (final c in starterCategories()) c.id};
    final again = {for (final c in starterCategories()) c.id};
    expect(once, hasLength(9));
    expect(once.intersection(again), isEmpty);
  });

  test('the demo book starts with the same categories as a new book', () {
    expect(
      demoLedger().categories.all.map(_look),
      starterCategories().map(_look),
    );
  });
}
