import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every on-off in the app is the tick in a circle (TickSwitch), so they
/// look and work the same everywhere: none of Material's own switches.
void main() {
  test('no Material Switch in the app', () {
    final found = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        if (RegExp(r'(^|[^\w])Switch(\.adaptive)?\(').hasMatch(line)) {
          found.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });
}
