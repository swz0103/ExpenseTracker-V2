import 'dart:convert';
import 'dart:io';

import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:drift/native.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:modular_persistence_probe/workflows.dart';
import 'package:modular_persistence_probe/database.dart';
import 'package:validated_restore_probe/restore_store.dart';
import 'package:validated_restore_probe/snapshot.dart';

/// Fixture runner only. Credential arguments are file paths, never secret values.
Future<void> main(List<String> args) async {
  if (args.length < 2)
    throw ArgumentError('Missing action and owned directory.');
  final directory = Directory(args[1]);
  if (args[0] == 'migrate' && args.length == 4) {
    final key = StorageKey(await File(args[2]).readAsBytes());
    final db = ProbeDatabase.withExecutor(
      NativeDatabase(
        File('${directory.path}/current.db'),
        setup: (raw) => configureEncryption(raw, key),
      ),
      migrationCheckpoint: (point) {
        if (point == args[3]) exit(73);
      },
    );
    try {
      await db.customSelect('SELECT * FROM events').get();
    } finally {
      await db.close();
    }
    return;
  }
  if (args[0] == 'recover' && args.length == 2) {
    await RestoreStore(directory).recover();
    return;
  }
  if (args[0] == 'restore' && args.length == 7) {
    if (!['password', 'recovery'].contains(args[4]))
      throw ArgumentError('Invalid credential mode.');
    final key = StorageKey(await File(args[5]).readAsBytes());
    final store = RestoreStore(
      directory,
      openDatabase: (file) => openEncrypted(file, key),
    );
    final envelope = await File(args[2]).readAsString();
    final credential = await File(args[3]).readAsString();
    await store.restore(
      envelope,
      password: args[4] == 'password' ? credential : null,
      recoveryKey: args[4] == 'recovery' ? credential : null,
      checkpoint: (point) {
        if (point == args[6]) exit(73);
      },
    );
    return;
  }
  if (args[0] == 'verify' && args.length == 4) {
    final key = StorageKey(await File(args[2]).readAsBytes());
    final expected = await File(args[3]).readAsString();
    final db = openEncrypted(File('${directory.path}/current.db'), key);
    try {
      final snapshot = SnapshotCodec();
      if (utf8.decode(await snapshot.capture(db)) != expected)
        throw StateError('Snapshot mismatch.');
      // Frozen v1 fixture operation: restore must retain idempotency history.
      final ws = WorkspaceId.parse('019f0000-0000-7000-8000-000000000000');
      final account = PostingAccount(
        id: PublicId.parse('019f0000-0000-7000-8000-000000000001'),
        workspace: ws,
        currency: Currency('USD', 2),
        expectedVersion: 1,
      );
      final result = await FinancialWorkflows(db).post(
        Posting.income(
          id: PublicId.generate(),
          operation: OperationKey(
            ws,
            OperationId.parse('019f0000-0000-7000-8000-000000000011'),
          ),
          date: BusinessDate(2026, 9, 26),
          account: account,
          amount: Money.parse(account.currency, '20'),
        ),
      );
      if (!result.replayed ||
          utf8.decode(await snapshot.capture(db)) != expected)
        throw StateError('Replay changed history.');
      if ((await db.customSelect('PRAGMA cipher_integrity_check').get())
          .isNotEmpty)
        throw StateError('Cipher integrity failure.');
    } finally {
      await db.close();
    }
    stdout.writeln('verified');
    return;
  }
  throw ArgumentError('Invalid fixture action.');
}
