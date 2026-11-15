import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'layout.dart';

/// Every library under `lib/src`, with the app libraries it imports or
/// exports, as paths from the app folder.
Map<String, List<String>> appImports() {
  final directive = RegExp(
    r'''^(?:import|export) '([^']+)'.*;''',
    multiLine: true,
  );
  final found = <String, List<String>>{};
  for (final file in Directory(Layout.src).listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    final path = file.uri.path;
    found[path] = [
      for (final match in directive.allMatches(file.readAsStringSync()))
        if (match[1]!.startsWith('package:expense_tracker/'))
          'lib/${match[1]!.substring('package:expense_tracker/'.length)}'
        else if (!match[1]!.contains(':'))
          File(path).parent.uri.resolve(match[1]!).path,
    ];
  }
  return found;
}

/// The app's layers, as docs/architecture.md sets them out:
///
/// - `core/`: what every feature shares, in six parts that each may use
///   only those listed for it below; it knows no feature and not how the
///   app is put together.
/// - `features/<name>/`: one feature each, in `model/`, `compose/` and
///   `ui/`; may use `core/`, and another feature's `model/` and
///   `compose/` but never its `ui/`; no two features need each other.
/// - `app/`: puts the app together; may use everything.
void main() {
  final imports = appImports();
  const screens = [...Layout.screenFolders, ...Layout.paintingDirs];
  String feature(String path) =>
      RegExp('${Layout.featuresDir}([^/]+)/').firstMatch(path)?[1] ?? '';

  test('every library sits in core, a feature or the app', () {
    for (final path in imports.keys) {
      expect(
        RegExp('^${Layout.src}/(core|app|features/[a-z_]+)/').hasMatch(path),
        isTrue,
        reason: path,
      );
    }
  });

  test('core knows no feature and not the app', () {
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      if (!file.startsWith(Layout.coreDir)) continue;
      for (final uri in uris) {
        expect(
          uri.startsWith(Layout.featuresDir) || uri.startsWith(Layout.appDir),
          isFalse,
          reason: '$file imports $uri',
        );
      }
    }
  });

  test('features do not reach into how the app is put together', () {
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      if (!file.startsWith(Layout.featuresDir)) continue;
      for (final uri in uris) {
        expect(uri.startsWith(Layout.appDir), isFalse, reason: '$file: $uri');
      }
    }
  });

  test('the ledger needs no screens; models need no screens', () {
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      final model =
          file.startsWith(Layout.ledgerDir) ||
          file.contains(Layout.modelFolder);
      if (!model) continue;
      for (final uri in uris) {
        expect(screens.any(uri.contains), isFalse, reason: '$file: $uri');
      }
    }
  });

  test('the ledger paints nothing: of Flutter, only foundation', () {
    // ChangeNotifier and ValueNotifier are plain Dart; colours are ARGB
    // ints, made into a Color by the page that paints them.
    final flutter = RegExp(r"import '(package:flutter/[^']+|dart:ui)'");
    for (final f in Directory(Layout.ledgerDir).listSync(recursive: true)) {
      if (f is! File) continue;
      for (final m in flutter.allMatches(f.readAsStringSync())) {
        expect(
          m[1],
          'package:flutter/foundation.dart',
          reason: '${f.path}: ${m[1]}',
        );
      }
    }
  });

  test('the ledger keeps to itself, and the book knows no storage', () {
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      if (!file.startsWith(Layout.ledgerDir)) continue;
      for (final uri in uris) {
        final inside =
            uri.startsWith(Layout.ledgerDir) ||
            Layout.ledgerMayImport.any(uri.startsWith);
        expect(inside, isTrue, reason: '$file: $uri');
        if (file != Layout.storageFile) {
          expect(uri, isNot(Layout.storageFile), reason: file);
        }
      }
    }
  });

  test('a feature has only model, ui and compose folders', () {
    for (final path in imports.keys) {
      final name = feature(path);
      if (name.isEmpty) continue;
      final inside = path.substring('${Layout.featuresDir}$name/'.length);
      expect(
        RegExp('^(${Layout.featureFolders.join('|')})/').hasMatch(inside),
        isTrue,
        reason: path,
      );
    }
  });

  test('only the preview reaches the made-up book', () {
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      if (file.startsWith(Layout.demoDir)) continue;
      for (final uri in uris) {
        expect(uri.contains('/demo/'), isFalse, reason: '$file: $uri');
      }
    }
  });

  test('core is in its parts, each using only those below it', () {
    // What each part of core may import from core, besides itself.
    const allowed = Layout.coreParts;
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      if (!file.startsWith(Layout.coreDir)) continue;
      final inside = file.substring(Layout.coreDir.length);
      if (inside == Layout.navigation) continue;
      final part = inside.split('/').first;
      expect(allowed.containsKey(part), isTrue, reason: file);
      for (final uri in uris) {
        if (!uri.startsWith(Layout.coreDir)) continue;
        final target = uri.substring(Layout.coreDir.length);
        final ok =
            target.startsWith('$part/') ||
            allowed[part]!.any(
              (other) => target == other || target.startsWith('$other/'),
            );
        expect(ok, isTrue, reason: '$file imports $uri');
      }
    }
  });

  test("a feature borrows another's model and forms, never its pages", () {
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      final from = feature(file);
      if (from.isEmpty) continue;
      for (final uri in uris) {
        final to = feature(uri);
        if (to.isEmpty || to == from) continue;
        expect(
          uri.contains('/features/$to/ui/'),
          isFalse,
          reason: '$file imports $uri',
        );
      }
    }
  });

  test('no two features need each other, even through others', () {
    final needs = <String, Set<String>>{};
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      final from = feature(file);
      if (from.isEmpty) continue;
      for (final uri in uris) {
        final to = feature(uri);
        if (to.isNotEmpty && to != from) {
          (needs[from] ??= {}).add(to);
        }
      }
    }
    // A feature reaching itself through those it needs is a cycle.
    for (final start in needs.keys) {
      final seen = <String>{};
      final todo = [...?needs[start]];
      while (todo.isNotEmpty) {
        final next = todo.removeLast();
        expect(next, isNot(start), reason: '$start needs itself: $needs');
        if (seen.add(next)) todo.addAll(needs[next] ?? const {});
      }
    }
  });

  test('pages open through Nav; a route is pushed in one place only', () {
    for (final file in imports.keys) {
      if (file == Layout.routePusher) continue;
      final text = File(file).readAsStringSync();
      expect(
        RegExp(r'Navigator(\.of\([^)]*\))?\s*\.\s*push').hasMatch(text),
        isFalse,
        reason: '$file pushes a route: use Nav, or openFlow for a task',
      );
    }
  });

  test('a file stays short enough to read in one go', () {
    // The made-up glyph paths are drawn by tool/glyphs.py, and the
    // ledger's own state is one class; every other file is split by
    // subject (tool/split.py) before it grows past the limit.
    for (final file in imports.keys) {
      final lines = File(file).readAsLinesSync().length;
      expect(
        lines,
        lessThanOrEqualTo(Layout.longer[file] ?? Layout.maxLines),
        reason: '$file has $lines lines',
      );
    }
  });
}
