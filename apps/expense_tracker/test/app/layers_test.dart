import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every library under `lib/src`, with the app libraries it imports or
/// exports, as paths from the app folder.
Map<String, List<String>> appImports() {
  final directive = RegExp(
    r'''^(?:import|export) '([^']+)'.*;''',
    multiLine: true,
  );
  final found = <String, List<String>>{};
  for (final file in Directory('lib/src').listSync(recursive: true)) {
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

/// The app's layers (docs/adr/0002-feature-folders.md):
///
/// - `core/`: the ledger, the look, shared widgets; it knows no feature
///   and not how the app is put together.
/// - `features/<name>/`: one feature each; may use `core/` and other
///   features, never `app/`.
/// - `app/`: puts the app together; may use everything.
void main() {
  final imports = appImports();
  const screens = ['/ui/', '/compose/', 'core/look/', 'core/charts/'];
  String feature(String path) =>
      RegExp(r'lib/src/features/([^/]+)/').firstMatch(path)?[1] ?? '';

  test('every library sits in core, a feature or the app', () {
    for (final path in imports.keys) {
      expect(
        RegExp(r'^lib/src/(core|app|features/[a-z_]+)/').hasMatch(path),
        isTrue,
        reason: path,
      );
    }
  });

  test('core knows no feature and not the app', () {
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      if (!file.startsWith('lib/src/core/')) continue;
      for (final uri in uris) {
        expect(
          uri.startsWith('lib/src/features/') || uri.startsWith('lib/src/app/'),
          isFalse,
          reason: '$file imports $uri',
        );
      }
    }
  });

  test('features do not reach into how the app is put together', () {
    // The lock screen still takes the file picker and Drive from the
    // platform channel; PR-3 hands them in instead.
    const pending = {
      'lib/src/features/lock/ui/lock_screen.dart': 'lib/src/app/platform.dart',
    };
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      if (!file.startsWith('lib/src/features/')) continue;
      for (final uri in uris) {
        if (pending[file] == uri) continue;
        expect(uri.startsWith('lib/src/app/'), isFalse, reason: '$file: $uri');
      }
    }
  });

  test('the ledger needs no screens; models need no screens', () {
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      final model =
          file.startsWith('lib/src/core/ledger/') || file.contains('/model/');
      if (!model) continue;
      for (final uri in uris) {
        expect(screens.any(uri.contains), isFalse, reason: '$file: $uri');
      }
    }
  });

  test('the ledger keeps to itself, and the book knows no storage', () {
    const store = 'lib/src/core/ledger/table_journal.dart';
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      if (!file.startsWith('lib/src/core/ledger/')) continue;
      for (final uri in uris) {
        final inside =
            uri.startsWith('lib/src/core/ledger/') ||
            uri == 'lib/src/core/perf.dart';
        expect(inside, isTrue, reason: '$file: $uri');
        if (file != store) expect(uri, isNot(store), reason: file);
      }
    }
  });

  test('a feature has only model, ui and compose folders', () {
    for (final path in imports.keys) {
      final name = feature(path);
      if (name.isEmpty) continue;
      final inside = path.substring('lib/src/features/$name/'.length);
      expect(
        RegExp(r'^(model|ui|compose)/').hasMatch(inside),
        isTrue,
        reason: path,
      );
    }
  });

  test('only the preview reaches the made-up book', () {
    for (final MapEntry(key: file, value: uris) in imports.entries) {
      if (file.startsWith('lib/src/app/demo/')) continue;
      for (final uri in uris) {
        expect(uri.contains('/demo/'), isFalse, reason: '$file: $uri');
      }
    }
  });
}
