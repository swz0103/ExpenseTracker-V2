import 'package:core/constants/category_colors.dart';
import 'package:test/test.dart';

void main() {
  test('new categories take the twelve colours in turn', () {
    expect(categoryColorValues, hasLength(12));
    expect(nextCategoryColor(0), 0xFF5B8DB0);
    expect(nextCategoryColor(1), 0xFFD08B5B);
    expect(nextCategoryColor(11), 0xFFB08AA6);
    // 12 % 12 = 0 and 25 % 12 = 1: round again after the last.
    expect(nextCategoryColor(12), 0xFF5B8DB0);
    expect(nextCategoryColor(25), 0xFFD08B5B);
  });
}
