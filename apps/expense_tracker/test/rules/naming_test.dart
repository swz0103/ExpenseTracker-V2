import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The made-up names docs/naming.md replaced with the usual words: none
/// may come back in the app's code or its tests. Comments are left out,
/// where an old name may be told as history.
void main() {
  const replaced = {
    'EntryBook': 'EntryRepository',
    'Recurrences': 'RecurringRepository',
    'ChangeSet': 'UnitOfWork',
    'QueryMemo': 'QueryCache',
    'Shelf': 'Collection',
    'TableJournal': 'SqlLedgerDataSource',
    'JournalFailure': 'DataSourceException',
    'EntryChecks': 'EntryValidator',
    'RowStore': 'EncryptedDatabase',
    'Place': 'AppRoute',
    'SectionPlace': 'SectionRoute',
    'SettingsPart': 'SettingsDestination',
    'openFlow': 'openFullScreen',
    'Keeper': 'BackupManager',
    'VaultKeeper': 'EncryptedBackupManager',
    'Connector': 'SyncJob',
    'Perf': 'PerformanceMonitor',
    'ProjectCard': 'TagSummaryCard',
  };

  test('no old made-up name comes back', () {
    final word = RegExp('(?<![\\w\$])(${replaced.keys.join('|')})(?![\\w\$])');
    final faults = <String>[];
    for (final top in ['lib', 'test', 'tool']) {
      for (final file in Directory(top).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        if (file.path.endsWith('naming_test.dart')) continue;
        for (final (i, line) in file.readAsLinesSync().indexed) {
          final code = line.split('//').first;
          for (final m in word.allMatches(code)) {
            faults.add(
              '${file.path}:${i + 1}: ${m[1]} is now ${replaced[m[1]]}',
            );
          }
        }
      }
    }
    expect(faults, isEmpty, reason: faults.join('\n'));
  });
}
