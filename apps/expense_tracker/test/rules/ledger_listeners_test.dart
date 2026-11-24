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
void main() {
  test('the scanner finds each way of following the whole ledger', () {
    expect(wholeLedger('      listenable: ledger,'), [1]);
    expect(wholeLedger('a\nlistenable: widget.ledger)'), [2]);
    expect(wholeLedger('changes: Listenable.merge([ledger, other]),'), [1]);
    // Over several lines, and not the first of the list.
    expect(
      wholeLedger('x\nListenable.merge([\n  ?prefs,\n  widget.ledger,\n]),'),
      [2],
    );
    expect(wholeLedger('merge([\n  ledger\n      .watch({Topic.a}),\n])'), []);
    expect(wholeLedger('listenable:\n    ledger,'), [1]);
    expect(wholeLedger('ledger\n    .addListener(f)'), [1]);
    expect(wholeLedger('widget.ledger.addListener(_changed);'), [1]);
    expect(wholeLedger('    changes: ledger,'), [1]);
    expect(wholeLedger('listenable: ledger.watch(const {Topic.entries}),'), []);
    expect(wholeLedger('listenable: ledger.amounts,'), []);
    expect(wholeLedger('ledger.problem.addListener(_report);'), []);
    expect(wholeLedger('// listenable: ledger,'), []);
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

/// A ledger named as what is listened to: `listenable:`, `animation:` or
/// `changes:` given the ledger itself, one of the `Listenable.merge` list
/// (on any line of it), or `ledger.addListener(`. Matched over the whole
/// file, so line breaks hide nothing.
final _whole = RegExp(
  r'(?:listenable|animation|changes)\s*:\s*(?:widget\.)?ledger\s*[,)]'
  r'|Listenable\.merge\(\s*\[[^\]]*?(?<![\w.])(?:widget\.)?ledger\s*[,\]]'
  r'|(?<![\w.])(?:widget\.)?ledger\s*\.\s*addListener\s*\(',
);

/// The lines of [source], from 1, where a way of following the whole
/// ledger starts; comment lines are not read.
List<int> wholeLedger(String source) {
  final code = [
    for (final line in source.split('\n'))
      line.trimLeft().startsWith('//') ? '' : line,
  ].join('\n');
  return [
    for (final m in _whole.allMatches(code))
      '\n'.allMatches(code.substring(0, m.start)).length + 1,
  ];
}
