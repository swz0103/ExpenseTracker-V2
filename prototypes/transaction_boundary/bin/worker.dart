import 'dart:convert';
import 'dart:io';

import 'package:transaction_boundary_probe/transaction_probe.dart';

void main(List<String> args) {
  if (args.length != 5) {
    stderr.writeln(
      'Expected database, workspace, operation, amount, checkpoint.',
    );
    exitCode = 64;
    return;
  }
  final probe = TransactionProbe(args[0]);
  try {
    final result = probe.transfer(
      workspaceId: args[1],
      operationId: args[2],
      minorUnits: int.parse(args[3]),
      onCheckpoint: (checkpoint) {
        // exit() skips finally: SQLite must recover from the process ending
        // without an explicit database close or a Dart-level rollback.
        if (checkpoint.name == args[4]) exit(73);
      },
    );
    stdout.writeln(
      jsonEncode({
        'operationId': result.operationId,
        'replayed': result.replayed,
      }),
    );
  } finally {
    probe.close();
  }
}
