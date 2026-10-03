import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:storage_sqlcipher/storage_sqlcipher.dart';

final class _AppendEvent implements Command<int> {
  _AppendEvent(this.operation, this.index);

  @override
  final OperationKey operation;
  final int index;

  @override
  String get input => 'crash-append-v1:$index';

  @override
  String encodeResult(int result) => '$result';

  @override
  int decodeResult(String encoded) => int.parse(encoded);
}

/// Usage: crash_worker <database> <hex key> <workspace id> <count>
///
/// Runs [count] commands, each appending one event, and prints
/// `committed <n>` after every commit so a parent can kill it mid-stream.
Future<void> main(List<String> args) async {
  if (args.length != 4) exit(64);
  final key = StorageKey.fromHex(args[1]);
  final store = SqlCipherStore.open(File(args[0]), key);
  final workspace = WorkspaceId.parse(args[2]);
  final runner = CommandRunner(store);
  final count = int.parse(args[3]);
  for (var i = 0; i < count; i++) {
    final operation = OperationKey(workspace, OperationId(PublicId.generate()));
    final command = _AppendEvent(operation, i);
    final outcome = await runner.run(command, (t) => _append(t, workspace, i));
    stdout.writeln('committed ${outcome.value}');
  }
  await stdout.flush();
  store.close();
}

Future<int> _append(SqlTransaction transaction, WorkspaceId workspace, int i) {
  return Future.value(
    transaction.append(
      id: PublicId.generate(),
      workspace: workspace,
      kind: 'crash.appended',
      payload: '{"index":$i}',
    ),
  );
}
