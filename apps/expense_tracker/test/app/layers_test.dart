import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'layout.dart';
import 'rule_exceptions.dart';

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
/// - `features/<name>/`: one feature each, in `model/`, `forms/` and
///   `ui/`; may use `core/`, and another feature's `model/` and
///   `forms/` but never its `ui/`; no two features need each other.
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

  test('inside the ledger, each folder uses only those below it', () {
    String? layerOf(String path) {
      final inside = path.substring(Layout.ledgerDir.length);
      for (final layer in Layout.ledgerLayers) {
        if (inside.startsWith(layer)) return layer;
      }
      return Layout.ledgerHelpers.contains(inside) ? 'helper' : null;
    }

    var checked = 0;
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      if (!file.startsWith(Layout.ledgerDir)) continue;
      final layer = layerOf(file);
      if (layer == null) continue; // persistence/ and ledger.dart
      final below = layer == 'helper'
          ? const ['models/']
          : Layout.ledgerLayers.sublist(0, Layout.ledgerLayers.indexOf(layer));
      for (final uri in uris) {
        if (!uri.startsWith(Layout.ledgerDir)) continue;
        checked++;
        final inside = uri.substring(Layout.ledgerDir.length);
        final allowed =
            layerOf(uri) == layer ||
            below.any(inside.startsWith) ||
            (layer != 'helper' && Layout.ledgerHelpers.contains(inside)) ||
            (layer == 'commands/' && Layout.commandsMayUse.contains(inside));
        expect(allowed, isTrue, reason: '$file uses $uri');
      }
    }
    // A rule that saw no import proves nothing.
    expect(checked, greaterThan(50));
  });

  test('the ledger keeps no words for the person: core/messages does', () {
    // Data the book itself holds (category names), and labels for the
    // diagnostics log, are allowed in a file marked `Exception to ledger
    // words` (rule_exceptions.dart).
    final words = RegExp(r"'[^']*[一-鿿][^']*'");
    for (final f in Directory(Layout.ledgerDir).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      if (excusedFile(lines, 'ledger words')) continue;
      for (final (i, line) in lines.indexed) {
        if (line.trimLeft().startsWith('//')) continue;
        expect(words.hasMatch(line), isFalse, reason: '${f.path}:${i + 1}');
      }
    }
  });

  test('a sum of prices or rates is worked out in whole numbers', () {
    // A double holds 662.05 only nearly, so a product that lands on a
    // half can round the wrong way: models/fixed_point.dart does it.
    final rounded = RegExp(r'\(([^()]*)\)\.round\(\)');
    final money = RegExp(
      r'\b(price|rate|move|shares|close)\b',
      caseSensitive: false,
    );
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('fixed_point.dart')) continue;
      for (final (i, line) in file.readAsLinesSync().indexed) {
        for (final m in rounded.allMatches(line)) {
          final sum = m[1]!;
          expect(
            sum.contains(RegExp('[*/]')) && money.hasMatch(sum),
            isFalse,
            reason: '${file.path}:${i + 1}: use timesPrice or roundedQuotient',
          );
        }
      }
    }
  });

  test('the ledger is in libraries of their own, not part files', () {
    for (final f in Directory(Layout.ledgerDir).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      expect(
        RegExp(r'^part (of )?', multiLine: true).hasMatch(f.readAsStringSync()),
        isFalse,
        reason: f.path,
      );
    }
  });

  test('a feature has only model, ui and forms folders', () {
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

  test('the ledger uses no more of Flutter than its notifiers', () {
    // So it can still become a pure Dart package (ADR-0012): only
    // foundation.dart, never widgets, material or the platform.
    final flutter = RegExp(
      r"^import 'package:flutter/([^']+)'",
      multiLine: true,
    );
    for (final file in imports.keys) {
      if (!file.contains('/core/ledger/')) continue;
      for (final m in flutter.allMatches(File(file).readAsStringSync())) {
        expect(
          m[1],
          'foundation.dart',
          reason: '$file: the ledger stays free of Flutter (ADR-0012)',
        );
      }
    }
  });

  test('fewer screens take the whole ledger', () {
    // A screen or a model that needs only the entries, or the reports,
    // takes that part (EntryReader, ReportService, exported by
    // ledger.dart): it says what it uses, and a test gives it only that.
    const most = 84;
    final whole = RegExp(r'\bLedger\b');
    var found = 0;
    for (final file in imports.keys) {
      if (!file.contains('/features/') && !file.contains('/src/app/')) continue;
      if (whole.hasMatch(File(file).readAsStringSync())) found++;
    }
    expect(found, lessThanOrEqualTo(most), reason: 'take only the part used');
    expect(found, most, reason: 'fewer now: lower `most` to $found');
  });

  test('casts of outside data only become fewer', () {
    // Read through JsonFields (core/formatting/json_fields.dart) instead: a cast
    // throws a TypeError for one field of the wrong kind and takes the
    // rest down with it. What is left is the ledger's own rows.
    const most = 18;
    final cast = RegExp(r' as (Map|List|String|num|int|bool|double|Object)\b');
    var found = 0;
    for (final file in imports.keys) {
      found += cast.allMatches(File(file).readAsStringSync()).length;
    }
    expect(found, lessThanOrEqualTo(most), reason: 'read it with JsonFields');
    expect(found, most, reason: 'fewer now: lower `most` to $found');
  });

  test('no two files of the app share a name', () {
    // A name found twice in a search is a file opened by mistake
    // (ADR-0009).
    final seen = <String, String>{};
    for (final file in imports.keys) {
      final name = file.split('/').last;
      final other = seen[name];
      expect(other, isNull, reason: '$file and $other share a name');
      seen[name] = file;
    }
  });

  test('the time is read from AppClock only', () {
    // Anything that depends on the day must be testable on any day: a
    // backup's age, a reminder, a file's name. core/time is the clock.
    for (final file in imports.keys) {
      if (file.contains('/core/time/')) continue;
      final lines = File(file).readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        if (line.trimLeft().startsWith('//')) continue;
        expect(
          line.contains('DateTime.now()'),
          isFalse,
          reason: '$file:${i + 1} reads the time: use AppClock.now()',
        );
      }
    }
  });

  test('a file past a screenful says why it is one file', () {
    // A guide, not a cap: past it a file is split by what it does, or
    // says at its top why it is better whole (`Exception to file length`),
    // such as the glyph paths tool/glyphs.py draws.
    for (final file in imports.keys) {
      final lines = File(file).readAsLinesSync();
      if (lines.length <= Layout.fileGuide) continue;
      expect(
        excusedFile(lines, 'file length'),
        isTrue,
        reason:
            '$file has ${lines.length} lines: split it by what it does, '
            'or say why it is one',
      );
    }
  });
}
