import 'dart:convert';
import 'dart:io';

import 'package:foundation_values/foundation_values.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:validated_restore_probe/snapshot.dart';

import 'android_slot_vault.dart';
import 'secure_key_slots.dart';

/// Device-only fixed fixture path, called after the runner's Android/debug guard.
Future<void> verifyGenerationRestores({
  required Directory root,
  required String envelope,
  required String recovery,
  required List<int> expected,
  required PostingAccount account,
}) async {
  final portable = SnapshotCodec(generationAware: true).canonicalize(expected);
  PublicId? previousSlot;
  for (final mode in ['password', 'recovery']) {
    // Persistent fixture directories allow a later app launch to reopen the
    // same pairs. Never delete a DB while leaving its secure slot unaccounted for.
    final directory = Directory('${root.path}/generation_v1_$mode');
    final store = LedgerStore(directory, SecureKeySlots(AndroidSlotVault()));
    final receipt = await store.restore(
      envelope,
      OperationId.parse(
        mode == 'password'
            ? '019f0000-0000-7000-8000-000000000031'
            : '019f0000-0000-7000-8000-000000000032',
      ),
      password: mode == 'password' ? 'android-synthetic-fixture-only' : null,
      recoveryKey: mode == 'recovery' ? recovery : null,
    );
    if (receipt.slot == previousSlot) {
      throw StateError('Shared target key slot');
    }
    previousSlot = receipt.slot;
    // Fresh adapters read platform storage again; this is still the same process.
    final reopened = LedgerStore(directory, SecureKeySlots(AndroidSlotVault()));
    final current = await reopened.generations.current();
    if (current?.receipt.slot != receipt.slot ||
        current?.receipt.generation != receipt.generation) {
      throw StateError('Pair mismatch');
    }
    final replay = await reopened.post(
      Posting.income(
        id: PublicId.generate(),
        operation: OperationKey(
          account.workspace,
          OperationId.parse('019f0000-0000-7000-8000-000000000011'),
        ),
        date: BusinessDate(2026, 9, 26),
        account: account,
        amount: Money.parse(account.currency, '20'),
      ),
    );
    if (!replay.replayed ||
        await reopened.balance(account) !=
            Money.parse(account.currency, '115') ||
        utf8.decode(await reopened.snapshot()) != utf8.decode(portable)) {
      throw StateError('Restored Ledger mismatch');
    }
    final raw = latin1.decode(
      await reopened.generations.databaseFile(receipt.generation).readAsBytes(),
    );
    if (raw.startsWith('SQLite format 3') ||
        raw.contains('Android fixture only')) {
      throw StateError('Plaintext detected');
    }
  }
}
