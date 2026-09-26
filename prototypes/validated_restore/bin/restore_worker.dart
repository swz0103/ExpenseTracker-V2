import 'dart:io';

import 'package:validated_restore_probe/restore_store.dart';

Future<void> main(List<String> args) async {
  if (args.length != 5)
    throw ArgumentError(
      'Expected owned directory, envelope, credential, mode, checkpoint.',
    );
  final store = RestoreStore(Directory(args[0]));
  final envelope = await File(args[1]).readAsString();
  final credential = await File(args[2]).readAsString();
  if (!['password', 'recovery'].contains(args[3]))
    throw ArgumentError('Unsupported credential mode.');
  await store.restore(
    envelope,
    password: args[3] == 'password' ? credential : null,
    recoveryKey: args[3] == 'recovery' ? credential : null,
    checkpoint: (point) {
      if (point == args[4]) exit(73);
    },
  );
}
