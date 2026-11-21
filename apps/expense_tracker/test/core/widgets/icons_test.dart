import 'package:expense_tracker/src/core/design_system/glyphs.dart';
import 'package:expense_tracker/src/core/widgets/icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a hundred category marks, each drawn and offered once', () {
    final keys = [
      for (final (_, marks) in categoryIconGroups)
        for (final (key, _) in marks) key,
    ];
    expect(keys, hasLength(100));
    expect(keys.toSet(), hasLength(100));
    final drawn = {for (final g in Glyph.values) g.name};
    for (final key in keys) {
      expect(drawn, contains(key), reason: key);
    }
  });

  test('each category mark has a name of its own to be read out', () {
    final names = [
      for (final (_, marks) in categoryIconGroups)
        for (final (key, name) in marks) (key, name),
    ];
    for (final (key, name) in names) {
      // Words, not the key it is kept by.
      expect(name, isNot(matches(RegExp('[A-Za-z]'))), reason: key);
    }
    expect({for (final (_, name) in names) name}, hasLength(100));
  });
}
