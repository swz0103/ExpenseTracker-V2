import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'layout.dart';

/// An error that is caught must not pass unseen: docs/conventions.md.
/// Every `catch` block in `lib` does one of three things: records the
/// error in the `ErrorLog`, throws it on, or says in a comment on its first
/// line why nothing needs doing, such as a file that cannot be read
/// leaving the defaults.
void main() {
  final clause = RegExp(
    r'\}\s*(?:on\s+[\w<>?, ]+?\s+)?catch\s*\([^)]*\)\s*\{|\}\s*on\s+[\w<>?]+\s*\{',
  );

  /// The text between the braces of the block that opens at [open].
  String block(String text, int open) {
    var depth = 0;
    for (var i = open; i < text.length; i++) {
      if (text[i] == '{') depth++;
      if (text[i] == '}' && --depth == 0) return text.substring(open + 1, i);
    }
    return text.substring(open + 1);
  }

  bool accounted(String body) {
    if (body.contains('ErrorLog.instance.record(')) return true;
    if (RegExp(r'\brethrow\b|\bthrow\b').hasMatch(body)) return true;
    final first = body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return first.startsWith('//');
  }

  test('a caught error is recorded, thrown on, or explained', () {
    final unseen = <String>[];
    for (final f in Directory(Layout.src).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      for (final m in clause.allMatches(text)) {
        final body = block(text, m.end - 1);
        if (accounted(body)) continue;
        final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
        unseen.add('${f.path}:$line');
      }
    }
    if (unseen.isNotEmpty) {
      fail(
        'Record these in ErrorLog.instance.record(...), rethrow, or start '
        'the block with a comment that says why nothing is needed:\n'
        '${unseen.join('\n')}',
      );
    }
  });

  test('an error is never put into a message as it is', () {
    // Its own words can hold a path or what the person wrote; say it with
    // ErrorLog.describe(error), which takes those out. Tests of the error
    // by its text (`'$error'.contains(...)`) and the scanner, which says
    // in words what went wrong, are the exceptions.
    final raw = RegExp(r'\$\{?(error|err|e)\}?(?![A-Za-z0-9_.(])');
    final said = <String>[];
    for (final f in Directory(Layout.src).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('/core/diagnostics/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (!raw.hasMatch(line) || line.contains('.contains(')) continue;
        if (f.path.endsWith('composer_pickers.dart') &&
            line.contains("_say('")) {
          continue;
        }
        said.add('${f.path}:${i + 1}');
      }
    }
    if (said.isNotEmpty) {
      fail(
        'Use ErrorLog.describe(error), not the error itself:\n${said.join('\n')}',
      );
    }
  });
}
