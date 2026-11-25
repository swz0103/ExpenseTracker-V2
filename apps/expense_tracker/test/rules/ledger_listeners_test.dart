import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// No page listens to the whole ledger (review 1, #13): each listens to
/// `ledger.watch(topics)`, the topics it reads, so a budget changed does
/// not build 帳戶 again, nor an entry 分類. A change of the day, a reload
/// or a reset tells every topic, and 隱藏金額 every watcher, so nothing a
/// page shows is left behind.
///
/// What still follows every change of the ledger is listed in [_allowed],
/// each with why; a new one is found here and must be given topics, or
/// a reason.
///
/// A part of the ledger handed on as a `Listenable` of its own (a
/// `ReminderBook`, a `WidgetBook`, followed with `book.addListener`) is
/// judged where it is made: `reminderBookOf` gives it
/// `ledger.watch(reminderTopics)`, `widgetBookOf` (overview.dart, in
/// [_allowed]) the whole ledger.
void main() {
  test('the scanner finds each way of following the whole ledger', () {
    expect(wholeLedger('      listenable: ledger,'), [1]);
    expect(wholeLedger('a\nlistenable: widget.ledger)'), [2]);
    expect(wholeLedger('changes: Listenable.merge([ledger, other]),'), [1]);
    // Over several lines, and not the first of the list: the line of the
    // ledger.
    expect(
      wholeLedger('x\nListenable.merge([\n  ?prefs,\n  widget.ledger,\n]),'),
      [4],
    );
    expect(wholeLedger('merge([\n  ledger\n      .watch({Topic.a}),\n])'), []);
    expect(wholeLedger('listenable:\n    ledger,'), [2]);
    expect(wholeLedger('ledger\n    .addListener(f)'), [1]);
    expect(wholeLedger('widget.ledger.addListener(_changed);'), [1]);
    expect(wholeLedger('    changes: ledger,'), [1]);
    expect(wholeLedger('listenable: ledger.watch(const {Topic.entries}),'), []);
    expect(wholeLedger('listenable: ledger.amounts,'), []);
    expect(wholeLedger('ledger.problem.addListener(_report);'), []);
    expect(wholeLedger('// listenable: ledger,'), []);
  });

  test('R20: other ways of writing the same are found too', () {
    for (final code in [
      'listenable: Listenable.merge(<Listenable>[ledger, p]),',
      'Listenable.merge({ledger, p})',
      'listenable: services.ledger,',
      'animation: widget.services.ledger,',
      'listenable: _ledger,',
      'listenable: ledger!,',
      'animation: (ledger), builder: b)',
      'Listenable.merge([a[0], ledger])',
      'merge([f(a[0]), ledger])',
      'Listenable.merge([ledger as Listenable])',
      'final add = ledger.addListener; add(f);',
      'AnimatedBuilder(animation: ledger, builder: b)',
      'listenable: // x\n ledger,',
      'Listenable.merge([a, ledger,])',
      'Listenable.merge([a.watch({X}), b[1], ledger])',
      'Listenable.merge([?ledger])',
      'parts.add(ledger);',
      'widget.ledger?.addListener(f)',
    ]) {
      expect(wholeLedger(code), isNotEmpty, reason: code);
    }
    // Through a variable: the list it is made of.
    expect(
      wholeLedger(
        'final parts = [ledger, p];\n'
        'final l = Listenable.merge(parts);\n'
        'ListenableBuilder(listenable: l,',
      ),
      [1],
    );
    expect(wholeLedger('Listenable.merge([ledger // all\n])'), [1]);
  });

  test('R20: what is not the ledger followed is not found', () {
    for (final code in [
      '/* listenable: ledger, */',
      "'listenable: ledger,'",
      "'''\nListenable.merge([ledger])\n'''",
      r'"${x} ledger.addListener(f)"',
      'listenable: Listenable.merge([ledger.watch({Topic.a}), p]),',
      'enum _Tab { overview, ledger, accounts }',
      'final tabs = [(_Tab.ledger, 1)];',
      'Form(this.initial, {this.ledger})',
      'f({Ledger Function()? ledger}) {}',
      'g({bool interactive = true, String? ledger}) {}',
      'show(context, ledger, other);',
      'book.addListener(run.ask);',
      'ledger.amounts.addListener(f);',
      'final m = {"a": ledger};',
    ]) {
      expect(wholeLedger(code), isEmpty, reason: code);
    }
  });

  test('no page listens to the whole ledger', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      for (final line in wholeLedger(f.readAsStringSync())) {
        if (_allowed.containsKey(path)) continue;
        found.add('$path:$line');
      }
    }
    expect(
      found,
      isEmpty,
      reason:
          'Listen to ledger.watch({the topics read}) instead, or add the '
          'file to _allowed with why it follows every change:\n'
          '${found.join('\n')}',
    );
  });

  test('what only hands the ledger on does not follow it', () {
    for (final path in _handedOn.keys) {
      expect(
        wholeLedger(File(path).readAsStringSync()),
        isEmpty,
        reason:
            '$path follows the whole ledger: give it topics, or move it '
            'to _allowed with why',
      );
      expect(File(path).readAsStringSync(), contains('ledger'));
    }
  });

  test('every file allowed still follows the whole ledger', () {
    for (final path in _allowed.keys) {
      expect(
        wholeLedger(File(path).readAsStringSync()),
        isNotEmpty,
        reason: '$path no longer follows the whole ledger: take it off',
      );
    }
  });
}

/// Files that take the ledger but do not follow it, and why: each only
/// hands it on, or reads it when something is pressed; what they show is
/// built by the pages and sections they hand it to, each on its topics.
const _handedOn = {
  'lib/src/app/shell.dart':
      'Listens to the ledger problem only; hands the ledger to each page.',
  'lib/src/features/entries/forms/composer_state.dart':
      'Gives the ledger to the form, which reads it as fields are changed; '
      'the open composer is not rebuilt by other changes.',
};

/// What follows every change of the ledger, and why: none of it is a page.
const _allowed = {
  'lib/src/app/lifecycle_services.dart':
      'The market feed: asks for the prices of what is held after any '
      'change, and does nothing when the holdings are the same.',
  'lib/src/features/overview/ui/overview.dart':
      'The home-screen widget (widgetBookOf): written again a moment '
      'after any change, as one file of sums from several topics.',
};

/// The ledger itself as a value: `ledger`, `_ledger`, `widget.ledger`,
/// `services.ledger`, `ledger!`, each reached through any chain of names
/// before it, and not a part of it read after (`ledger.watch(…)`,
/// `ledger.amounts`). A `(…)` around it or an `as …` after it changes
/// nothing.
const _ledger =
    r'(?<![\w.$])\(*\s*(?:\w+\s*!?\s*\??\.\s*)*_?ledger\b\s*!?'
    r'(?:\s+as\s+[\w<>?]+)?\s*\)*(?!\s*(?:\??\.|\(|\[|\w))';

/// The ways of following the whole ledger: `listenable:`, `animation:` or
/// `changes:` given the ledger; the ledger as an element of a list or a
/// set (as handed to `Listenable.merge`, there or through a variable) or
/// added to one; and the ledger's own `addListener`, called or torn off.
final _whole = RegExp(
  '(?:listenable|animation|changes)\\s*:\\s*(?<named>$_ledger)\\s*[,)]'
  '|(?<=(?:[\\[{,]|[\\[{,]\\s*\\?)\\s*)(?<element>$_ledger)\\s*[,\\]}]'
  '|\\.\\s*add\\s*\\(\\s*(?<added>$_ledger)\\s*\\)'
  r'|(?<![\w.$])(?<listener>(?:\w+\s*!?\s*\??\.\s*)*_?ledger)\s*!?\s*\??\.'
  r'\s*addListener\b',
);

/// [source] with its comments and the insides of its strings blanked out,
/// line breaks kept: what is written there neither trips the rule nor
/// hides anything from it.
String codeOf(String source) {
  final out = StringBuffer();
  var i = 0;
  final n = source.length;
  void blank(int to) {
    for (; i < to && i < n; i++) {
      out.write(source[i] == '\n' ? '\n' : ' ');
    }
  }

  bool at(String s) => source.startsWith(s, i);
  while (i < n) {
    if (at('//')) {
      final end = source.indexOf('\n', i);
      blank(end < 0 ? n : end);
    } else if (at('/*')) {
      // Block comments nest in Dart.
      var depth = 0;
      var j = i;
      while (j < n) {
        if (source.startsWith('/*', j)) {
          depth++;
          j += 2;
        } else if (source.startsWith('*/', j)) {
          depth--;
          j += 2;
          if (depth == 0) break;
        } else {
          j++;
        }
      }
      blank(j);
    } else if (source[i] == "'" || source[i] == '"') {
      final raw =
          i > 0 &&
          source[i - 1] == 'r' &&
          (i < 2 || !RegExp(r'[\w$]').hasMatch(source[i - 2]));
      final quote = source.startsWith(source[i] * 3, i)
          ? source[i] * 3
          : source[i];
      var j = i + quote.length;
      // Interpolations are blanked with the string around them.
      var braces = 0;
      while (j < n) {
        if (!raw && source[j] == r'\') {
          j += 2;
        } else if (!raw && braces == 0 && source.startsWith(r'${', j)) {
          braces = 1;
          j += 2;
        } else if (braces > 0) {
          if (source[j] == '{') braces++;
          if (source[j] == '}') braces--;
          j++;
        } else if (source.startsWith(quote, j)) {
          j += quote.length;
          break;
        } else if (quote.length == 1 && source[j] == '\n') {
          break;
        } else {
          j++;
        }
      }
      blank(j);
    } else {
      out.write(source[i]);
      i++;
    }
  }
  return out.toString();
}

/// Where the bracket open at [at] in [code] that is closed last stands:
/// a `(`, `[` or `{`; null at the top.
int? _openAt(String code, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    switch (code[i]) {
      case ')' || ']' || '}':
        depth++;
      case '(' || '[' || '{':
        if (depth == 0) return i;
        depth--;
    }
  }
  return null;
}

/// Whether [m], a ledger after a `[`, `{` or `,`, is an element of a list
/// or a set: not an argument of a call or a record, a parameter (named
/// `this.ledger`) or a value of an enum.
bool _isElement(String code, RegExpMatch m) {
  if (m.namedGroup('element')!.trimLeft().startsWith('this.')) return false;
  final open = _openAt(code, code.indexOf(RegExp(r'[^\s(]'), m.start));
  if (open == null) return false;
  return switch (code[open]) {
    '[' => true,
    '{' => !RegExp(r'enum\s+\w+\s*$').hasMatch(code.substring(0, open)),
    _ => false,
  };
}

/// The lines of [source], from 1, where a way of following the whole
/// ledger is written; comments and strings are not read.
List<int> wholeLedger(String source) {
  final code = codeOf(source);
  return [
    for (final m in _whole.allMatches(code))
      if (m.namedGroup('element') == null || _isElement(code, m))
        '\n'
                .allMatches(code.substring(0, code.indexOf('ledger', m.start)))
                .length +
            1,
  ];
}
