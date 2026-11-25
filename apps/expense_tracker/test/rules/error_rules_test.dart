import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/layout.dart';
import '../support/rule_exceptions.dart';

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
    // by its text (`'$error'.contains(...)`) are let through, and a line
    // marked `Exception to error words` (rule_exceptions.dart).
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
        if (excusedAt(lines, i, 'error words')) continue;
        said.add('${f.path}:${i + 1}');
      }
    }
    if (said.isNotEmpty) {
      fail(
        'Use ErrorLog.describe(error), not the error itself:\n${said.join('\n')}',
      );
    }
  });

  // D84: no technical words reach the person. An error becomes words only
  // in core/messages/problem_messages.dart (describeProblem, problemNote,
  // failureNote), which never say the error itself.
  final source = [
    for (final f in Directory(Layout.src).listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f,
  ];

  /// The lines of [files] matching [pattern], not in a comment, not
  /// excused as `Exception to error words`, outside [_elsewhere].
  List<String> found(Iterable<File> files, RegExp pattern) => [
    for (final f in files)
      if (!_elsewhere.any(f.path.endsWith))
        for (final (i, line) in f.readAsLinesSync().indexed)
          if (!line.trimLeft().startsWith('//') &&
              pattern.hasMatch(line) &&
              !excusedAt(f.readAsLinesSync(), i, 'error words'))
            '${f.path}:${i + 1}',
  ];

  test('ErrorLog.describe is for the log, never the screen', () {
    final said = found(
      source.where((f) => !f.path.contains('/core/diagnostics/')),
      RegExp(r'ErrorLog\.describe\('),
    );
    expect(
      said,
      isEmpty,
      reason:
          'Tell the person with problemNote/failureNote; ErrorLog.describe '
          'only where it goes to a log or a file, marked so',
    );
  });

  test('describeProblem is a sentence of its own, not put after words', () {
    final said = found(source, RegExp(r'\$\{\s*describeProblem\('));
    expect(
      said,
      isEmpty,
      reason: "Use problemNote('what did not happen', error)",
    );
  });

  test('a screen never says an exception\'s own message or code', () {
    final screens = source.where(
      // The adapters under app/android read a platform error's code to
      // sort it; they show nothing.
      (f) =>
          f.path.contains('/ui/') ||
          (f.path.contains(Layout.appDir) && !f.path.contains('/android/')),
    );
    final said = found(
      screens,
      RegExp(r'\b(error|e|err|exception|problem)\.(message|code|osError)\b'),
    );
    expect(said, isEmpty, reason: 'Say it with problemNote or failureNote');
  });

  test('the finder sees raw errors and lets marked ones through', () {
    final dir = Directory.systemTemp.createTempSync('d84');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/x.dart')
      ..writeAsStringSync(
        "  a('\${ErrorLog.describe(error)}');\n"
        '  // Exception to error words: into a file.\n'
        '  b(ErrorLog.describe(error));\n',
      );
    expect(found([file], RegExp(r'ErrorLog\.describe\(')), ['${file.path}:1']);
  });
}

/// Files whose error words go elsewhere than the screen: DriveException
/// keeps Drive's answer (ErrorLog.describe) in its detail, for the log
/// only; the screens say a DriveProblem through driveNote
/// (backup/model/restore_sources.dart).
const _elsewhere = <String>{'features/backup/model/drive_backup.dart'};
