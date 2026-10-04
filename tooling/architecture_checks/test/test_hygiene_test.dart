import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every package: a test must say which failure it expects;
/// `throwsA(anything)` passes for a crash too (health check G1-15).
const strictPackages = [
  'apps/expense_tracker',
  'infrastructure/backup_security',
  'infrastructure/backup_service',
  'infrastructure/drive_backup',
  'infrastructure/ledger_backup',
  'infrastructure/ledger_sqlcipher',
  'infrastructure/ledger_vault',
  'infrastructure/market_adapters',
  'infrastructure/storage_sqlcipher',
  'packages/accounts',
  'packages/amount_input',
  'packages/app_core',
  'packages/bookkeeping',
  'packages/budgets',
  'packages/categories',
  'packages/credit_cards',
  'packages/data_exchange',
  'packages/foundation_values',
  'packages/investments',
  'packages/ledger',
  'packages/market_data',
  'packages/merchants',
  'packages/recurring_transactions',
  'packages/reports',
  'packages/tags',
];

final _vague = RegExp(r'throwsA\(\s*(anything|isA<(Object|Exception)>\(\))');

void main() {
  test('tests in new packages name the failure they expect', () {
    final root = p.normalize(p.join(Directory.current.path, '..', '..'));
    final offenders = <String>[];
    for (final package in strictPackages) {
      final tests = Directory(p.join(root, package, 'test'));
      if (!tests.existsSync()) continue;
      for (final file in tests.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_vague.hasMatch(lines[i])) {
            offenders.add('${p.relative(file.path, from: root)}:${i + 1}');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
