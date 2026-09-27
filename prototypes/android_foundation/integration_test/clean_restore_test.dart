import 'dart:convert';
import 'dart:io';

import 'package:android_foundation/android_catalog_protection.dart';
import 'package:android_foundation/android_key_vault.dart';
import 'package:android_foundation/android_slot_vault.dart';
import 'package:android_foundation/secure_key_slots.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ledger/ledger.dart';
import 'package:ledger_generation_probe/ledger_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:validated_restore_probe/snapshot.dart';

// Prepare this app's clean_input directory after clearing ONLY the fixture app.
// Supply envelope, expected public fixture and ONE credential; never source keys.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const mode = String.fromEnvironment('PROBE_MODE');
  testWidgets('Clean Android $mode restore and persisted replay', (
    tester,
  ) async {
    expect(['password', 'recovery'], contains(mode));
    final support = await getApplicationSupportDirectory();
    expect(await AndroidKeyVault().read(), isNull);
    expect(
      Directory('${support.path}/foundation_fixture_v1').existsSync(),
      isFalse,
    );
    final input = Directory('${support.path}/clean_input');
    expect(input.listSync().map((file) => file.uri.pathSegments.last).toSet(), {
      'envelope.json',
      'credential.txt',
      'expected.json',
    });
    final envelope = await File('${input.path}/envelope.json').readAsString();
    final credential = await File('${input.path}/credential.txt')
        .readAsString();
    final expected = SnapshotCodec(generationAware: true)
        .canonicalize(await File('${input.path}/expected.json').readAsBytes());
    final account = PostingAccount(
      id: PublicId.parse('019f0000-0000-7000-8000-000000000001'),
      workspace: WorkspaceId.parse('019f0000-0000-7000-8000-000000000000'),
      currency: Currency('USD', 2),
      expectedVersion: 1,
    );
    LedgerStore open() => LedgerStore(
      Directory('${support.path}/clean_target'),
      SecureKeySlots(AndroidSlotVault()),
      catalogProtection: androidCatalogProtection(
        PublicId.parse('019f0000-0000-7000-8000-000000000050'),
      ),
    );
    final store = open();
    final prior = await store.generations.current();
    final receipt = await store.restore(
      envelope,
      OperationId.parse('019f0000-0000-7000-8000-000000000051'),
      password: mode == 'password' ? credential : null,
      recoveryKey: mode == 'recovery' ? credential : null,
    );
    if (prior != null) {
      expect(receipt.generation, prior.receipt.generation);
      expect(receipt.slot, prior.receipt.slot);
    }
    final reopened = open();
    expect(await reopened.snapshot(), expected);
    expect(
      await reopened.balance(account),
      Money.parse(account.currency, '115'),
    );
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
    expect(replay.replayed, isTrue);
    expect(await reopened.snapshot(), expected);
    expect(await AndroidKeyVault().read(), isNull);
    final raw = await reopened.generations
        .databaseFile(receipt.generation)
        .readAsBytes();
    expect(latin1.decode(raw).startsWith('SQLite format 3'), isFalse);
    // Nonsecret identities let the host compare fresh-process launches.
    await File('${support.path}/clean_result.json').writeAsString(
      jsonEncode({
        'mode': mode,
        'generation': receipt.generation.value,
        'slot': receipt.slot.value,
        'balanceMinor': '11500',
        'replayed': replay.replayed,
      }),
      flush: true,
    );
  });
}
