import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:foundation_values/foundation_values.dart';
import 'package:storage_generation_probe/fixture_key_slots.dart';
import 'package:storage_generation_probe/generation_store.dart';
import 'package:storage_generation_probe/fixture_catalog_protection.dart';

Future<void> main(List<String> args) async {
  if (args.length != 5 &&
      !(args.length == 6 &&
          ['protected', 'protected-upgrades'].contains(args[5])))
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
    upgradeAware: args.length == 6 && args[5] == 'protected-upgrades',
  );
  try {
    if (args[0] == 'hold') {
      await directory.create(recursive: true);
      final handle = await File('${directory.path}/lifecycle.lock')
          .open(mode: FileMode.append);
      try {
        await handle.lock(FileLock.exclusive);
        stdout.writeln('locked');
        await stdout.flush();
        await stdin.first;
        await handle.unlock();
      } finally {
        await handle.close();
      }
    } else if (args[0] == 'upgrade') {
      final request = UpgradeRequest.decode(File(args[2]).readAsStringSync());
      await store.upgrade(
        request,
        (source) async => PreparedUpgrade(
          args[3],
          sha256
              .convert(utf8.encode('synthetic-backup:${source.value}'))
              .toString(),
        ),
        checkpoint: (point) {
          if (point == args[4]) exit(73);
        },
      );
    } else if (args[0] == 'install') {
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
