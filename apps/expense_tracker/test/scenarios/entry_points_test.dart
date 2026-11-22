import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every library `lib/main.dart` reaches inside this app.
Set<String> reachable(String entry) {
  final seen = <String>{};
  final pending = [entry];
  final directive = RegExp(
    r'''^(?:import|export) '([^']+)';''',
    multiLine: true,
  );
  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    if (!seen.add(path)) continue;
    final source = File(path).readAsStringSync();
    for (final match in directive.allMatches(source)) {
      final uri = match[1]!;
      if (uri.startsWith('package:expense_tracker/')) {
        pending.add('lib/${uri.substring('package:expense_tracker/'.length)}');
      } else if (!uri.contains(':')) {
        pending.add(File(path).parent.uri.resolve(uri).toFilePath());
      } else {
        seen.add(uri);
      }
    }
  }
  return seen;
}

void main() {
  test('the production entry never reaches the memory preview', () {
    final libraries = reachable('lib/main.dart');
    expect(libraries, contains('lib/src/app/bootstrap.dart'));
    expect(libraries, contains('package:vault/ledger_vault.dart'));
  });

  test('the preview entry uses made-up data only', () {
    final libraries = reachable('lib/main_preview.dart');
    expect(libraries, contains('lib/src/app/demo/seed.dart'));
    expect(libraries, isNot(contains('lib/src/app/bootstrap.dart')));
    const vault = 'package:vault/ledger_vault.dart';
    expect(libraries, isNot(contains(vault)));
    // The web build has no database: nothing may reach the backups either.
    const backups = 'package:vault/ledger_backup.dart';
    expect(libraries, isNot(contains(backups)));
    expect(libraries, isNot(contains('package:storage/storage.dart')));
  });
}
