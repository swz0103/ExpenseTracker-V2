import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The writing rules of docs/conventions.md that a test can hold: every
/// document opens with its one-line summary, stays short enough to read
/// in one go, and every link in it leads somewhere.
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

  test('a document opens with its summary and stays under 150 lines', () {
    for (final f in docs) {
      // A decision record keeps the shape of ADR-0001, its status first.
      if (f.path.contains('${p.separator}adr${p.separator}')) continue;
      final lines = f.readAsLinesSync();
      final name = p.relative(f.path, from: root);
      final first = lines.skip(1).firstWhere((l) => l.trim().isNotEmpty);
      expect(first, startsWith('> '), reason: '$name: no summary line');
      expect(lines.length, lessThanOrEqualTo(150), reason: name);
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
}
