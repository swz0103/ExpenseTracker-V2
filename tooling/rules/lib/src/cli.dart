import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'engine.dart';
import 'ratchet.dart';
import 'registry.dart';

/// The repository root above [start]: the folder that holds `apps/` and
/// `packages/`.
String findRoot(String start) {
  var dir = p.normalize(p.absolute(start));
  while (true) {
    if (Directory(p.join(dir, 'apps')).existsSync() &&
        Directory(p.join(dir, 'packages')).existsSync()) {
      return dir;
    }
    final parent = p.dirname(dir);
    if (parent == dir) {
      throw StateError('no folder with apps/ and packages/ above $start');
    }
    dir = parent;
  }
}

const _usage = '''
Usage: dart run tooling/rules/bin/check.dart [options]
  --rule <id>       check one rule only
  --list            print the rule ids and what each prevents
  --update          rewrite the baseline (refuses to grow it)
  --allow-growth    with --update: accept new violations into the baseline
  --help            this text
''';

/// Runs the checker; returns the exit code (0 ok, 1 broken, 2 bad usage).
/// [root] is the repository root, found from the current folder when null.
int runCheck(
  List<String> args, {
  String? root,
  required StringSink out,
  required StringSink err,
  List<Rule> rules = allRules,
}) {
  var doUpdate = false;
  var allowGrowth = false;
  var list = false;
  String? only;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--update':
        doUpdate = true;
      case '--allow-growth':
        allowGrowth = true;
      case '--list':
        list = true;
      case '--rule':
        if (i + 1 >= args.length) {
          err.writeln('--rule needs an id\n$_usage');
          return 2;
        }
        only = args[++i];
      case '--help':
        out.write(_usage);
        return 0;
      default:
        err.writeln('unknown option ${args[i]}\n$_usage');
        return 2;
    }
  }
  if (list) {
    for (final r in rules) {
      out.writeln('${r.id}  ${r.purpose}');
    }
    return 0;
  }
  if (allowGrowth && !doUpdate) {
    err.writeln('--allow-growth only makes sense with --update');
    return 2;
  }
  final selected = [
    for (final r in rules)
      if (only == null || r.id == only) r,
  ];
  if (selected.isEmpty) {
    err.writeln('no rule with id $only (see --list)');
    return 2;
  }
  final base = root ?? findRoot(Directory.current.path);
  final ids = {for (final r in selected) r.id};
  final project = Project.discover(base);
  final violations = [for (final r in selected) ...r.check(project)];
  final current = countViolations(violations, ids);

  final baselinePath = p.join(base, baselineFile);
  final baselineText = File(baselinePath);
  final baseline = baselineText.existsSync()
      ? decodeBaseline(baselineText.readAsStringSync())
      : <String, Map<String, int>>{};

  if (doUpdate) {
    final result = update(
      current,
      baseline,
      rules: ids,
      allowGrowth: allowGrowth,
    );
    if (result.refused.isNotEmpty) {
      err.writeln('Refusing to grow the baseline:');
      for (final line in result.refused) {
        err.writeln('  $line');
      }
      err.writeln('Fix the new violations, or pass --allow-growth on purpose.');
      return 1;
    }
    baselineText.writeAsStringSync(encodeBaseline(result.baseline));
    out.writeln('Baseline written to $baselineFile.');
    return 0;
  }

  final report = compare(current, baseline, rules: only == null ? null : ids);
  if (report.ok) {
    out.writeln('Rules: ok (${selected.length} rules, baseline holds).');
    return 0;
  }
  if (report.growth.isNotEmpty) {
    err.writeln('New violations (not allowed by the baseline):');
    for (final line in report.growth) {
      err.writeln('  $line');
    }
    final grown = {
      for (final line in report.growth)
        RegExp(r'^\[([^\]]+)\] (\S+):').firstMatch(line)!.group(2)!,
    };
    err.writeln('\nWhere:');
    for (final v in violations) {
      if (grown.contains(v.file)) err.writeln('  $v');
    }
  }
  if (report.stale.isNotEmpty) {
    err.writeln('\nThe baseline is stale: fewer violations than recorded.');
    for (final line in report.stale) {
      err.writeln('  $line');
    }
    err.writeln(
      'The list only shrinks: run `dart run tooling/rules/bin/check.dart '
      '--update` and commit $baselineFile.',
    );
  }
  return 1;
}
