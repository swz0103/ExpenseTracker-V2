import 'package:expense_tracker/src/core/look/glyphs.dart';
import 'package:expense_tracker/src/core/ui/icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a hundred category marks, each drawn and offered once', () {
    final keys = [for (final (_, keys) in categoryIconGroups) ...keys];
    expect(keys, hasLength(100));
    expect(keys.toSet(), hasLength(100));
    final drawn = {for (final g in Glyph.values) g.name};
    for (final key in keys) {
      expect(drawn, contains(key), reason: key);
    }
  });
}
