import 'dart:io';

import 'package:architecture_checks/baseline_protection.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _dir = 'apps/expense_tracker/test/baseline';

void main() {
  group('changedBaselineFiles', () {
    test('adding baseline files is always fine', () {
      expect(changedBaselineFiles('A\t$_dir/new_test.dart\n'), isEmpty);
    });

    test('modifying or deleting an existing baseline file is reported', () {
      final changed = changedBaselineFiles(
        'M\t$_dir/a_test.dart\nD\t$_dir/golden/b.json\nA\t$_dir/c_test.dart\n',
      );
      expect(changed, ['$_dir/a_test.dart', '$_dir/golden/b.json']);
    });

    test('files outside the baseline are ignored', () {
      expect(
        changedBaselineFiles(
          'M\tapps/expense_tracker/test/known_defects/a_test.dart\n'
          'D\tapps/expense_tracker/test/baseline_helpers.dart\n'
          'M\t$_dir.txt\n',
        ),
        isEmpty,
      );
    });

    test('a rename away from the baseline counts as a deletion', () {
      expect(changedBaselineFiles('R100\t$_dir/a_test.dart\tlib/a.dart\n'), [
        '$_dir/a_test.dart',
      ]);
    });

    test('a type change is reported and quoted paths are unquoted', () {
      expect(changedBaselineFiles('T\t"$_dir/\\344\\270\\255.json"\n'), [
        '$_dir/\\344\\270\\255.json',
      ]);
    });

    test('empty and malformed lines are skipped', () {
      expect(changedBaselineFiles('\n\nnonsense\n'), isEmpty);
    });
  });

  group('hasBaselineReason', () {
    test('finds the line among other commit messages', () {
      expect(
        hasBaselineReason(
          'Fix a bug\n\nBody\n\nBaseline-Change: rounding is now half-up\n\n'
          'Another commit\n',
        ),
        isTrue,
      );
    });

    test('needs a reason after the colon', () {
      expect(hasBaselineReason('Baseline-Change:\n'), isFalse);
      expect(hasBaselineReason('Baseline-Change:   \n'), isFalse);
    });

    test('needs to start a line', () {
      expect(hasBaselineReason('see Baseline-Change: x\n'), isFalse);
    });

    test('no commit message means no reason', () {
      expect(hasBaselineReason(''), isFalse);
    });
  });

  group('check_baseline_change.dart in a real repository', () {
    late Directory repo;
    late String base;
    final script = p.join(
      Directory.current.path,
      'bin',
      'check_baseline_change.dart',
    );

    String run(List<String> args) {
      final result = Process.runSync('git', [
        '-c',
        'user.name=t',
        '-c',
        'user.email=t@example.com',
        ...args,
      ], workingDirectory: repo.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return (result.stdout as String).trim();
    }

    void write(String path, String text) {
      File(p.join(repo.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }

    // Run from the temporary repository, resolving packages as this one does.
    ProcessResult check() => Process.runSync(Platform.resolvedExecutable, [
      '--packages=${p.join(Directory.current.path, '.dart_tool', 'package_config.json')}',
      script,
      base,
    ], workingDirectory: repo.path);

    setUp(() {
      repo = Directory.systemTemp.createTempSync('baseline-');
      run(['init', '-q']);
      write('$_dir/old.txt', 'v1');
      run(['add', '-A']);
      run(['commit', '-qm', 'base']);
      base = run(['rev-parse', 'HEAD']);
    });

    tearDown(() => repo.deleteSync(recursive: true));

    test('adding a baseline file passes', () {
      write('$_dir/new.txt', 'x');
      run(['add', '-A']);
      run(['commit', '-qm', 'add']);
      expect(check().exitCode, 0);
    });

    test('modifying one fails without a reason and passes with one', () {
      write('$_dir/old.txt', 'v2');
      run(['commit', '-qam', 'change']);
      final failed = check();
      expect(failed.exitCode, 1);
      expect(failed.stderr, contains('$_dir/old.txt'));
      run(['commit', '-q', '--allow-empty', '-m', 'why\n\nBaseline-Change: x']);
      expect(check().exitCode, 0);
    });

    test('deleting one without a reason fails', () {
      File(p.join(repo.path, _dir, 'old.txt')).deleteSync();
      run(['commit', '-qam', 'delete']);
      expect(check().exitCode, 1);
    });
  });
}
