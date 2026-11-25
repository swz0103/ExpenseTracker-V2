import 'dart:io';

import 'package:expense_tracker/src/core/platform/app_files.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Kotlin side decides nothing and says nothing of its own (NAT-1,
/// review 32): words, file names and the backups' rules are the app's,
/// handed over or mirrored in one file each with a test holding them to
/// the app (NativeWords.kt: native_messages_test, widget_words_test;
/// AppFiles.kt: app_files_test). Rule B9 reads only Dart, so this reads
/// the Kotlin code: outside those two files, no string holds Chinese
/// text, none is one of the app's file names, none is a backup's file
/// ending, and no day or week is written in milliseconds.
///
/// Comments are left out, and so are the unit and device tests, which
/// write what the app hands over as literals on purpose.
void main() {
  const root = 'android/app/src';
  const flavors = ['main', 'sideload', 'play'];

  /// Where each kind is allowed.
  const wordsFile = 'NativeWords.kt';
  const namesFile = 'AppFiles.kt';

  /// The few strings that are an app file's name by chance, each with why
  /// it is not one.
  const allowed = <String, Set<String>>{
    // WorkManager's names for the jobs and the update channel's id.
    'BackupWorker.kt': {'backups'},
    'UpdateWorker.kt': {'updates'},
    'SelfUpdate.kt': {'updates'},
    // A channel argument's name and an error code.
    'PhotosHandler.kt': {'camera'},
    'BackupsHandler.kt': {'backups'},
  };

  final han = RegExp('[　-鿿＀-￯]');
  final dayInMillis = RegExp(
    r'86_?400_?000|604_?800_?000|24L?\s*\*\s*60\s*\*\s*60',
  );
  final names = AppFiles.all.values.toSet();

  /// Each string literal of [code] with its line, comments taken out.
  Iterable<(int, String)> strings(String code) sync* {
    final lines = code.split('\n');
    var inBlock = false;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (inBlock) {
        final end = line.indexOf('*/');
        if (end < 0) continue;
        line = line.substring(end + 2);
        inBlock = false;
      }
      line = line.replaceAll(RegExp(r'/\*.*?\*/'), '');
      final open = line.indexOf('/*');
      if (open >= 0) {
        line = line.substring(0, open);
        inBlock = true;
      }
      line = line.replaceFirst(RegExp(r'(^|\s)//.*'), '');
      for (final m in RegExp(r'"((?:[^"\\]|\\.)*)"').allMatches(line)) {
        yield (i + 1, m[1]!);
      }
    }
  }

  /// What is wrong with the Kotlin file named [name] holding [code].
  List<String> faults(String name, String code) => [
    for (final (line, text) in strings(code))
      if (name != wordsFile && han.hasMatch(text))
        '$name:$line: Chinese text "$text": hand it over, or keep a '
            'fallback in $wordsFile'
      else if (name != namesFile &&
          names.contains(text) &&
          !(allowed[name]?.contains(text) ?? false))
        '$name:$line: the file name "$text": AppFiles.kt'
      else if (name != namesFile && text.endsWith('.etbk'))
        '$name:$line: a backup\'s name "$text": handed over by BackupRules',
    for (final (i, line) in code.split('\n').indexed)
      if (!line.trimLeft().startsWith('*') &&
          !line.trimLeft().startsWith('//') &&
          dayInMillis.hasMatch(line))
        '$name:${i + 1}: a day or week in milliseconds: handed over by '
            'BackupRules',
  ];

  test('the scan finds what it looks for', () {
    expect(
      faults('X.kt', '''
// "註解" is no code
/* "記帳本" in a comment */
val a = "記帳本"
val b = File(dir, "preferences.json")
val c = "記帳本-\$mark-x.etbk"
val d = 7 * 24L * 60 * 60 * 1000
val e = "plain"
val f = "old.etbk"
'''),
      hasLength(5),
    );
    expect(faults('NativeWords.kt', 'const val A = "記帳本"'), isEmpty);
    expect(faults('AppFiles.kt', 'const val A = "outbox"'), isEmpty);
    expect(faults('BackupWorker.kt', 'const val NAME = "backups"'), isEmpty);
  });

  test('no Kotlin file but the two keeps the app\'s words, names or rules', () {
    final found = <String>[];
    var files = 0;
    for (final flavor in flavors) {
      final folder = Directory('$root/$flavor');
      if (!folder.existsSync()) continue;
      for (final file in folder.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.kt')) continue;
        files++;
        found.addAll(
          faults(file.uri.pathSegments.last, file.readAsStringSync()),
        );
      }
    }
    expect(files, greaterThan(40));
    expect(found, isEmpty);
  });

  test('the allow-list names only strings still there', () {
    for (final MapEntry(key: name, value: texts) in allowed.entries) {
      // SelfUpdate.kt is in both flavors; the strings of every copy.
      final there = {
        for (final flavor in flavors)
          if (Directory('$root/$flavor').existsSync())
            for (final f in Directory(
              '$root/$flavor',
            ).listSync(recursive: true))
              if (f is File && f.uri.pathSegments.last == name)
                for (final (_, t) in strings(f.readAsStringSync())) t,
      };
      expect(there, containsAll(texts), reason: name);
    }
  });
}
