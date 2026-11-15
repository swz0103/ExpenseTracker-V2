import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// How tests are written (docs/conventions.md): a control is pressed by
/// its key from core/look/keys.dart, so a test keeps working when the
/// words on a button change. Words are looked for only to check them,
/// or to press a piece of the book itself, such as an entry or account.
void main() {
  test('tests press controls by their key, not their words', () {
    // The book's own entries and accounts, the page's title tapped as
    // somewhere else on the screen, and widgets the tests make.
    const content = {'週末點心', '日常銀行', '收支紀錄', 'open', '第一站'};
    final pressed = RegExp(r"(tap|longPress)\(find\.text\('([^']+)'\)");
    for (final f in Directory('test').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('_test.dart')) continue;
      for (final m in pressed.allMatches(f.readAsStringSync())) {
        expect(
          content,
          contains(m[2]),
          reason: '${f.path}: press 「${m[2]}」 by its key (Keys)',
        );
      }
    }
  });
}
