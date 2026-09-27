import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';

Future<void> main(List<String> args) async {
  if (args.length != 5 && !(args.length == 6 && args[5] == 'protected'))
    exit(64);
  final directory = Directory(args[1]);
  final protected = args.length == 6;
  final slots = FixtureKeySlots(
    Directory(protected ? '${directory.path}-keys' : '${directory.path}/keys'),
  );
  final store = GenerationStore(
    directory,
    slots,
    catalogProtection: protected ? fixtureCatalogProtection(slots) : null,
  );
  try {
    if (args[0] == 'install') {
      await store.install(
        args[3],
        OperationId.parse(args[2]),
        checkpoint: (point) {
          if (point == args[4]) exit(73);
        },
      );
    } else if (args[0] == 'verify') {
      final current = await store.current();
      if (args[3] == '<none>') {
        if (current != null) exit(65);
      } else if (current == null ||
          current.value != args[3] ||
          current.receipt.operation.toString() != args[2]) {
        exit(65);
      }
    } else {
      exit(64);
    }
  } catch (_) {
    stderr.writeln('Generation probe failed');
    exit(70);
  }
}
