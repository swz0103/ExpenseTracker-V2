import 'dart:io';

import 'package:rules/src/cli.dart';

/// Checks the rulebook against the baseline. Run from anywhere in the
/// repository:
///
///     dart run tooling/rules/bin/check.dart [--update] [--rule <id>] [--list]
void main(List<String> args) {
  exitCode = runCheck(args, out: stdout, err: stderr);
}
