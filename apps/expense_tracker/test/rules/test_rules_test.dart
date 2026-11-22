import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// How tests are written (docs/conventions.md): a control is pressed by
/// its key from core/design_system/keys.dart, so a test keeps working when the
/// words on a button change. Words are looked for only to check them,
/// or to press a piece of the book itself, such as an entry or account.
void main() {
  test('tests press controls by their key, not their words', () {
    // The book's own entries and accounts, the page's title tapped as
    // somewhere else on the screen, and widgets the tests make. Anything
    // else is pressed by its key, or as a screen reader would (`go`).
    const content = {'週末點心', '日常銀行', '收支紀錄', 'open', '第一站'};
    final pressed = RegExp(
      r'\.(tap|longPress|drag|press|ensureVisible)\w*\(\s*'
      r'find\.(text|textContaining|widgetWithText)\(([^)]*)\)',
    );
    final faults = <String>[];
    for (final top in ['test', 'integration_test']) {
      for (final f in Directory(top).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (final m in pressed.allMatches(f.readAsStringSync())) {
          final words = RegExp(r"^'([^']*)'$").firstMatch(m[3]!.trim())?[1];
          if (!content.contains(words)) {
            faults.add('${f.path}: press ${m[3]} by its key (Keys) or `go`');
          }
        }
      }
    }
    expect(faults, isEmpty, reason: faults.join('\n'));
  });

  test('a test sits where the file it tests sits', () {
    // lib/src/a/b.dart is tested in test/a/b_test.dart, so whether a
    // file has its test shows at a glance (docs/conventions.md). What is not about
    // one file has a folder of its own.
    const apart = [
      'rules',
      'scenarios',
      'support',
      'perf',
      'tool',
      'baseline',
      'known_defects',
    ];
    final faults = <String>[];
    for (final file in Directory('test').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('_test.dart')) continue;
      final path = file.path.replaceAll(r'\\', '/').substring('test/'.length);
      if (apart.contains(path.split('/').first)) continue;
      final tested =
          'lib/src/${path.substring(0, path.length - '_test.dart'.length)}.dart';
      if (!File(tested).existsSync()) faults.add('test/$path: no $tested');
    }
    expect(faults, isEmpty, reason: faults.join('\n'));
  });
}
