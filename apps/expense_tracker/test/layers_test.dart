import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the libraries in [folder] import, by file.
Map<String, List<String>> importsIn(String folder) {
  final directive = RegExp(r'''^import '([^']+)'.*;''', multiLine: true);
  return {
    for (final file in Directory(folder).listSync())
      if (file is File && file.path.endsWith('.dart'))
        file.path: [
          for (final match in directive.allMatches(file.readAsStringSync()))
            match[1]!,
        ],
  };
}

/// The app's layers: the model knows nothing of screens or storage, and
/// storage nothing of screens.
void main() {
  const screens = ['../look/', '../pages/', '../compose/', '../charts/'];

  test('the model needs no screens and no storage', () {
    final model = importsIn('lib/src/model');
    for (final MapEntry(key: file, value: imports) in model.entries) {
      for (final uri in imports) {
        final screen = screens.any(uri.startsWith);
        final widgets =
            uri == 'package:flutter/material.dart' ||
            uri == 'package:flutter/widgets.dart';
        expect(
          screen || widgets || uri.startsWith('../book/'),
          isFalse,
          reason: '$file imports $uri',
        );
      }
    }
  });

  test('storage needs no screens', () {
    final book = importsIn('lib/src/book');
    for (final MapEntry(key: file, value: imports) in book.entries) {
      for (final uri in imports) {
        expect(screens.any(uri.startsWith), isFalse, reason: '$file: $uri');
      }
    }
  });
}
