import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';

Future<void> main(List<String> args) async {
  try {
    final store = LedgerStore(
      Directory(args[0]),
      FixtureKeySlots(Directory(args[1])),
    );
    final envelope = File(args[2]).readAsStringSync();
    final credential = File(args[3]).readAsStringSync();
    await store.restore(
      envelope,
      OperationId.parse(args[4]),
      password: args[5] == 'password' ? credential : null,
      recoveryKey: args[5] == 'recovery' ? credential : null,
      checkpoint: (point) {
        if (point == args[6]) exit(73);
      },
    );
    File(args[7]).writeAsBytesSync(await store.snapshot(), flush: true);
  } catch (_) {
    stderr.writeln('Ledger worker failed');
    exit(70);
  }
}
