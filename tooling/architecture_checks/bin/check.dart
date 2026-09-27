import 'dart:io';

import 'package:architecture_checks/check.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run bin/check.dart <repository-root>');
    exitCode = 64;
    return;
  }
  try {
    final issues = checkWorkspace(Directory(args.single));
    for (final issue in issues) {
      stderr.writeln(issue);
    }
    if (issues.isNotEmpty) {
      exitCode = 1;
    } else {
      stdout.writeln('Architecture boundaries passed.');
    }
  } catch (_) {
    stderr.writeln(
      'Architecture check could not read a valid workspace/policy.',
    );
    exitCode = 1;
  }
}
