import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The writing rules of docs/conventions.md that a test can hold: every
/// document opens with its one-line summary, stays short enough to read
/// in one go, every link in it leads somewhere, every file it names is
/// there, and every decision record has its line in the index.
void main() {
  final root = p.normalize(p.join(Directory.current.path, '..', '..'));
  final docs = [
    for (final f in Directory(p.join(root, 'docs')).listSync(recursive: true))
      if (f is File && f.path.endsWith('.md')) f,
  ];
  final readmes = [
    File(p.join(root, 'README.md')),
    for (final top in ['apps', 'packages', 'infrastructure'])
      for (final d in Directory(p.join(root, top)).listSync())
        if (d is Directory && File(p.join(d.path, 'README.md')).existsSync())
          File(p.join(d.path, 'README.md')),
  ];

  test('a document opens with its summary', () {
    // No cap on length: one at 150 lines was split or squeezed to fit,
    // which made it harder to read, not easier.
    for (final f in docs) {
      // A decision record keeps the shape of ADR-0001, its status first.
      if (f.path.contains('${p.separator}adr${p.separator}')) continue;
      final lines = f.readAsLinesSync();
      final name = p.relative(f.path, from: root);
      final first = lines.skip(1).firstWhere((l) => l.trim().isNotEmpty);
      expect(first, startsWith('> '), reason: '$name: no summary line');
    }
  });

  test('every link in the documents leads to a file that is there', () {
    final link = RegExp(r'\]\(([^)#\s]+)(?:#[^)]*)?\)');
    for (final f in [...docs, ...readmes]) {
      for (final m in link.allMatches(f.readAsStringSync())) {
        final target = m.group(1)!;
        if (target.startsWith('http')) continue;
        final path = p.normalize(p.join(p.dirname(f.path), target));
        expect(
          FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound,
          isTrue,
          reason: '${p.relative(f.path, from: root)} links to $target',
        );
      }
    }
  });

  test('every source file a current document names is there', () {
    // Decision records, the change log and the review keep the names of
    // their day.
    const history = ['adr', 'CHANGELOG.md', 'roadmap.md'];
    // A path in back quotes with a source file's extension, matched by its
    // tail so a document can name it from its own folder.
    final named = RegExp(
      r'`([\w./-]+\.(?:dart|kt|kts|md|yaml|yml|xml|py|sh))`',
    );
    final placeholder = RegExp(r'(^|/)(a|NNNN)[/-]');
    final listed = Process.runSync('git', ['ls-files'], workingDirectory: root);
    final files = (listed.stdout as String).split('\n');
    final faults = <String>[];
    for (final f in [...docs, ...readmes]) {
      final name = p.relative(f.path, from: root);
      if (history.any(name.contains)) continue;
      for (final m in named.allMatches(f.readAsStringSync())) {
        final path = m.group(1)!;
        if (placeholder.hasMatch(path)) continue;
        if (!files.any((x) => x == path || x.endsWith('/$path'))) {
          faults.add('$name names $path');
        }
      }
    }
    expect(faults, isEmpty);
  });

  test('every decision record has its line in the index', () {
    final index = File(p.join(root, 'docs', 'README.md')).readAsStringSync();
    for (final f in Directory(p.join(root, 'docs', 'adr')).listSync()) {
      final adr = p.basename(f.path);
      expect(index, contains('(adr/$adr)'), reason: '$adr is not indexed');
    }
  });
}
