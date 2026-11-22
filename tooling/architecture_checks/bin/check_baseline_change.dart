import 'dart:io';

import 'package:architecture_checks/baseline_protection.dart';

/// Pull-request gate for rule C3 (see lib/baseline_protection.dart):
///
///     dart run tooling/architecture_checks/bin/check_baseline_change.dart <base>
///
/// where <base> is the pull request's base commit. Run in the repository
/// with the full history of the pull request checked out.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: check_baseline_change.dart <base-ref>');
    exit(2);
  }
  final base = args.single;
  final diff = await _git([
    'diff',
    '--no-renames',
    '--name-status',
    '$base...HEAD',
  ]);
  final changed = changedBaselineFiles(diff);
  if (changed.isEmpty) {
    stdout.writeln('No existing baseline file is changed.');
    return;
  }
  final log = await _git(['log', '$base..HEAD', '--format=%B']);
  if (hasBaselineReason(log)) {
    stdout.writeln(
      'Baseline files changed, with a Baseline-Change reason:\n'
      '${changed.map((f) => '  $f').join('\n')}',
    );
    return;
  }
  stderr.writeln(
    'These existing baseline files are modified or deleted:\n'
    '${changed.map((f) => '  $f').join('\n')}\n'
    'Add a line "Baseline-Change: <reason>" to a commit message of this pull '
    'request to say why the recorded behaviour changes.',
  );
  exit(1);
}

Future<String> _git(List<String> args) async {
  final result = await Process.run('git', args);
  if (result.exitCode != 0) {
    stderr.writeln('git ${args.join(' ')} failed:\n${result.stderr}');
    exit(2);
  }
  return result.stdout as String;
}
