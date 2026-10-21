import 'dart:io';

import 'package:storage/storage.dart';

/// Usage: crash_worker <database> <hex key> <count>
///
/// Makes [count] writes, each keeping two records together, and prints
/// `committed <n>` after every commit so a parent can kill it mid-stream.
Future<void> main(List<String> args) async {
  if (args.length != 3) exit(64);
  final store = RowStore.open(File(args[0]), StorageKey.fromHex(args[1]));
  final count = int.parse(args[2]);
  for (var i = 0; i < count; i++) {
    store.write((w) {
      w.put('entry', 'e$i', '{"index":$i}');
      w.put('pair', 'p$i', '{"index":$i}');
    });
    stdout.writeln('committed ${i + 1}');
  }
  await stdout.flush();
  store.close();
}
