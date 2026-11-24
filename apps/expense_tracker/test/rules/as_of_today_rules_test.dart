import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/rule_exceptions.dart';

/// One "as of today" predicate everywhere (D25, D71): every sum, count,
/// "latest" or "usual" over the book's entries takes them through
/// `countedOn` (packages/ledger/entries, model/planned.dart), so a 預定
/// entry joins on its day and nowhere earlier. This test finds each read
/// of the entries in `lib` — `entries.all`, `.inMonth(`, `.onDay(` and
/// `entriesBetween(` — and wants it handed straight to `countedOn(`, or
/// to the holdings' `replay(`, which takes the entries through it itself.
///
/// The few reads that rightly need every entry carry a comment
/// `// Exception to as-of-today: <why>` on the line or just above it
/// (rule_exceptions.dart): an export, the integrity check, a search over
/// everything, duplicate checks, write rules over the whole timeline,
/// lists that show 預定 entries marked as such, and lookups by id.
void main() {
  test('the scanner tells a read through the predicate from one without', () {
    expect(unpredicated('for (final e in _entries.all) {}'), [1]);
    expect(unpredicated('for (final e in countedOn(_entries.all, t)) {}'), []);
    expect(
      unpredicated('x = countedOn(\n  _entries.inMonth(y, m),\n  t,\n);'),
      [],
    );
    expect(unpredicated('a;\nfinal d = ledger.entries.onDay(day);'), [2]);
    expect(unpredicated('f(countedOn(x, t), entriesBetween(e, a, b));'), [1]);
    expect(unpredicated('h.replay(_entries.all, today: t);'), []);
    expect(unpredicated('return book\n    .entries\n    .inMonth(y, m);'), [2]);
    expect(unpredicated('// for (final e in _entries.all)'), []);
    expect(
      unpredicated(
        '// Exception to as-of-today: an export.\n'
        'for (final e in _entries.all) {}',
      ),
      [],
    );
  });

  test('sums and counts over the entries go through countedOn', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final line in unpredicated(f.readAsStringSync())) {
        found.add('${f.path}:$line');
      }
    }
    if (found.isNotEmpty) {
      fail(
        'Take these through countedOn(entries, today), or mark why every '
        'entry is wanted with `// Exception to as-of-today: <why>`:\n'
        '${found.join('\n')}',
      );
    }
  });
}

/// A read of the book's entries.
final _read = RegExp(
  r'(?<![A-Za-z0-9])_?(?:entries|book)\s*\.\s*(?:all\b|inMonth\s*\(|onDay\s*\()'
  r'|(?<![\w.])entriesBetween\s*\(',
);

/// The calls a read may be handed to: the predicate, and the holdings'
/// replay, which applies it.
const _through = {'countedOn', 'replay'};

/// The lines of [source], from 1, that read the entries without the
/// predicate and are not marked as an exception.
List<int> unpredicated(String source) {
  final lines = source.split('\n');
  // Comments are blanked, keeping every offset, so a read in one is not
  // seen.
  final code = [
    for (final l in lines) l.trimLeft().startsWith('//') ? ' ' * l.length : l,
  ].join('\n');
  final found = <int>{};
  for (final m in _read.allMatches(code)) {
    if (_declares(code, m.start)) continue;
    if (_handedTo(code, m.start)) continue;
    final line = '\n'.allMatches(code.substring(0, m.start)).length;
    if (excusedAt(lines, line, 'as-of-today')) continue;
    found.add(line + 1);
  }
  return found.toList()..sort();
}

/// Whether the match at [at] names a function being declared, as
/// `List<Entry> entriesBetween(`, rather than calling one.
bool _declares(String code, int at) =>
    RegExp(r'(?:List|Iterable)<Entry>\s+$')
        .hasMatch(code.substring(at < 40 ? 0 : at - 40, at));

/// Whether the read at [at] is an argument of a call in [_through]: the
/// call whose parenthesis it sits in, the statement not left.
bool _handedTo(String code, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    final c = code[i];
    if (c == ')' || c == ']') {
      depth++;
    } else if (c == '[') {
      if (depth == 0) return false;
      depth--;
    } else if (c == '(') {
      if (depth > 0) {
        depth--;
        continue;
      }
      final name = RegExp(r'(\w+)\s*$').firstMatch(code.substring(0, i));
      return name != null && _through.contains(name[1]);
    } else if (depth == 0 && (c == ';' || c == '{' || c == '}')) {
      return false;
    }
  }
  return false;
}
