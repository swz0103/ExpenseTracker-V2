import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/rule_exceptions.dart';

/// D82, one rule: a change that can be undone is not asked first, it is
/// told with 復原 (`showUndo`, design_system/feedback.dart); one that
/// cannot be undone is asked first (`confirm`). Every deletion, archive,
/// merge, import and budget taken away is one of the two.
enum Safety {
  /// Told with 復原 by `showUndo`, in the same function that does it.
  undo,

  /// Asked first by `confirm`, in the same function that does it.
  confirm,

  /// Not something the person does: what an undo itself runs, or what
  /// the book does by itself; called only from the ledger, or from the
  /// undo a note runs.
  none,
}

/// Every destructive action of the book, by the call that does it, and
/// how it is made safe. A new one (a command method whose name says it
/// takes something away) fails the second test until it is listed here.
const _actions = <String, Safety>{
  // Entries, from the form, a swipe or many picked: `deleteEntries`.
  'removeAll': Safety.undo,
  'remove': Safety.undo,
  // Deleted entries emptied for good with the account they name (D78).
  'discardTrashed': Safety.confirm,
  // Tags and merchants: renamed, merged into another or taken off.
  'renameTag': Safety.undo,
  'renameMerchant': Safety.undo,
  // An import (`addImport`, which runs `addAll`).
  'addImport': Safety.undo,
  'removeAccount': Safety.undo,
  'setArchived': Safety.undo,
  'mergeCategory': Safety.undo,
  'removeBudget': Safety.undo,
  'removeRecurring': Safety.undo,
  // The book replaced: by the sample data, or by a backup.
  'resetTo': Safety.confirm,
  'restoreAnother': Safety.confirm,
  // The backup password taken off; new keys made.
  'removeBackupPassphrase': Safety.confirm,
  'resetKeys': Safety.confirm,
  // What an undo runs.
  'takeBack': Safety.none,
  // The trash emptied of what is past its time, as the day turns.
  'expireTrash': Safety.none,
};

/// The words a command's name starts with when it takes something away.
final _destructive = RegExp(
  r'^(remove|delete|discard|merge|rename|archive|setArchived|reset|expire|'
  r'clear|drop|takeBack|purge|empty|restoreAnother)',
);

/// The command and ledger files whose public methods are the book's
/// actions.
const _commandFiles = [
  'lib/src/core/ledger/ledger.dart',
  'lib/src/features/backup/model/backup_manager.dart',
];

/// A public method declared on a member line: `  Type name(`.
final _method = RegExp(r'^  (?! )(?:[\w<>?, ]+ )?([a-z]\w*)\(');

/// The function around line [at] of [lines]: from the member or top-level
/// line that opens it to the next one.
String _enclosing(List<String> lines, int at) {
  // A top-level line, or a member declared with its type: `  Type name(`.
  bool opens(String line) =>
      RegExp(r'^[A-Za-z@]').hasMatch(line) ||
      RegExp(r'^  [\w<>?,. ]*[\w>?] [a-z_]\w*\(').hasMatch(line) &&
          !RegExp(
            r'^\s*(if|for|while|switch|try|catch|on|else|return|final|var|'
            r'late|const|await|do|assert|throw)\b',
          ).hasMatch(line);
  var start = at;
  while (start > 0 && !opens(lines[start])) {
    start--;
  }
  var end = at + 1;
  while (end < lines.length && !opens(lines[end])) {
    end++;
  }
  return lines.sublist(start, end).join('\n');
}

/// The places in [lines] that call an action of [_actions] without what
/// its [Safety] asks for, each as `line: action → missing`, from 1.
List<String> unsafeIn(List<String> lines) {
  final found = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('//')) continue;
    for (final MapEntry(key: action, value: safety) in _actions.entries) {
      if (safety == Safety.none) continue;
      // On a command, the ledger or the backup manager; or a function of
      // its own, such as addImport.
      final call = RegExp(
        '(?:Commands|[Mm]anager|ledger)\\.$action\\(|(?:^|[^\\w.])$action\\(',
      );
      if (!call.hasMatch(line)) continue;
      // Its own declaration.
      if (RegExp('^\\s*[\\w<>?]+ $action\\(').hasMatch(line)) continue;
      if (excusedAt(lines, i, 'undo rule')) continue;
      final body = _enclosing(lines, i);
      final needs = safety == Safety.undo ? 'showUndo(' : 'confirm(';
      if (!body.contains(needs)) found.add('${i + 1}: $action → $needs');
    }
  }
  return found;
}

void main() {
  test('the finder reads the function around a call', () {
    expect(
      unsafeIn([
        '  void _go() {',
        '    final undo = ledger.budgetCommands.removeBudget(name);',
        "    showUndo(context, '已刪除', undo!);",
        '  }',
      ]),
      isEmpty,
    );
    expect(
      unsafeIn([
        '  void _go() {',
        '    ledger.budgetCommands.removeBudget(name);',
        '  }',
        '  void _other() {',
        "    showUndo(context, '已刪除', () {});",
        '  }',
      ]),
      ['2: removeBudget → showUndo('],
    );
    expect(
      unsafeIn([
        '  Future<void> _go() async {',
        "    if (!await confirm(context, '刪除？', '刪除')) return;",
        '    ledger.entryCommands.discardTrashed(trashed);',
        '  }',
      ]),
      isEmpty,
    );
    expect(
      unsafeIn([
        '  void _go() {',
        '    // Exception to undo rule: a test of the mark.',
        '    ledger.resetTo(fresh);',
        '  }',
      ]),
      isEmpty,
    );
  });

  test('every destructive action is undone or asked first (D82)', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      // The ledger's own commands call one another.
      if (f.path.startsWith('lib/src/core/ledger/')) continue;
      for (final hit in unsafeIn(f.readAsLinesSync())) {
        found.add('${f.path}:$hit');
      }
    }
    if (found.isNotEmpty) {
      fail(
        'Tell a change that can be undone with showUndo, and ask before '
        'one that cannot (D82), or mark a rightful case with '
        '`// Exception to undo rule: <why>`:\n${found.join('\n')}',
      );
    }
  });

  test('a new destructive action is listed with how it is made safe', () {
    final files = [
      for (final f in Directory('lib/src/core/ledger/commands').listSync())
        if (f is File && f.path.endsWith('.dart')) f.path,
      ..._commandFiles,
    ];
    final unlisted = <String>{};
    for (final path in files) {
      for (final line in File(path).readAsLinesSync()) {
        final name = _method.firstMatch(line)?[1];
        if (name == null || !_destructive.hasMatch(name)) continue;
        if (!_actions.containsKey(name)) unlisted.add('$path: $name');
      }
    }
    expect(
      unlisted,
      isEmpty,
      reason: 'List each in _actions with its Safety (D82)',
    );
  });

  test('archiving goes through the commands that give back an undo', () {
    final found = <String>[];
    for (final f in Directory('lib/src/features').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      for (final m in RegExp(r'copyWith\(\s*archived:').allMatches(text)) {
        found.add(
          '${f.path}:${'\n'.allMatches(text.substring(0, m.start)).length + 1}',
        );
      }
    }
    expect(found, isEmpty, reason: 'Use setArchived, which gives an Undo');
  });
}
