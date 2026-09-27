import 'dart:io';

import 'package:android_foundation/android_slot_vault.dart';
import 'package:android_foundation/key_access.dart';
import 'package:android_foundation/secure_key_slots.dart';
import 'package:encrypted_storage_probe/encrypted_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class _SlotKeyVault implements KeyVault {
  _SlotKeyVault(this.slot);
  final String slot;
  final vault = AndroidSlotVault();
  @override
  Future<String?> read() => vault.read(slot);
  @override
  Future<void> write(String value) => vault.write(slot, value);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Platform slots preserve existing and invalid values', (
    tester,
  ) async {
    final vault = AndroidSlotVault();
    final slots = SecureKeySlots(vault);
    final missing = PublicId.generate();
    await expectLater(slots.read(missing), throwsA(isA<KeyUnavailable>()));
    expect(await vault.read(missing.value), isNull);
    final existing = PublicId.generate();
    await slots.create(existing);
    final original = await vault.read(existing.value);
    await expectLater(slots.create(existing), throwsA(isA<KeyUnavailable>()));
    expect(await vault.read(existing.value) == original, isTrue);
    await SecureKeySlots(AndroidSlotVault()).read(existing);
    final malformed = PublicId.generate();
    await vault.write(malformed.value, 'v2:unsupported-fixture');
    await expectLater(slots.read(malformed), throwsA(isA<KeyUnavailable>()));
    expect(await vault.read(malformed.value), 'v2:unsupported-fixture');
  });

  testWidgets('Existing encrypted file with missing slot gets no replacement', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final keyId = PublicId.generate();
    final slots = SecureKeySlots(AndroidSlotVault());
    await slots.create(keyId);
    final key = await slots.read(keyId);
    final file = File('${support.path}/missing-slot-${keyId.value}.db');
    final db = openEncrypted(file, key);
    try {
      await db.customSelect('SELECT count(*) FROM accounts').get();
    } finally {
      await db.close();
    }
    final before = await file.readAsBytes();
    final absent = _SlotKeyVault(PublicId.generate().value);
    await expectLater(
      KeyAccess(absent).load(databaseExists: file.exists),
      throwsA(isA<KeyUnavailable>()),
    );
    expect(await absent.read(), isNull);
    expect(await file.readAsBytes(), before);
  });

  for (final point in ['column', 'index']) {
    testWidgets('Android encrypted migration rollback after $point and retry', (
      tester,
    ) async {
      final support = await getApplicationSupportDirectory();
      final sql = await File('${support.path}/fixture_input/v1.sql')
          .readAsString();
      final slot = PublicId.generate();
      final slots = SecureKeySlots(AndroidSlotVault());
      await slots.create(slot);
      final key = await slots.read(slot);
      final file = File('${support.path}/migration-${slot.value}.db');
      final initial = sqlite3.open(file.path);
      configureEncryption(initial, key);
      initial.execute(sql);
      initial.close();
      Object state() {
        final raw = sqlite3.open(file.path);
        try {
          configureEncryption(raw, key);
          return [
            raw.userVersion,
            raw
                .select(
                  'SELECT type,name,sql FROM sqlite_master ORDER BY type,name',
                )
                .map((r) => r.values.toList())
                .toList(),
            for (final table in [
              'accounts',
              'events',
              'legs',
              'openings',
              'allocations',
              'receipts',
              'audit',
            ])
              raw
                  .select('SELECT * FROM $table ORDER BY rowid')
                  .map((r) => r.values.toList())
                  .toList(),
          ];
        } finally {
          raw.close();
        }
      }

      final before = state();
      final attempted = openEncrypted(
        file,
        key,
        migrationCheckpoint: (p) {
          if (p == point) throw StateError('Injected migration failure');
        },
      );
      try {
        await expectLater(
          attempted.customSelect('SELECT * FROM events').get(),
          throwsA(isA<StateError>()),
        );
      } finally {
        await attempted.close();
      }
      expect(state(), before);
      final retry = openEncrypted(
        file,
        await SecureKeySlots(AndroidSlotVault()).read(slot),
      );
      try {
        expect(
          (await retry.customSelect('PRAGMA user_version').get()).single
              .read<int>('user_version'),
          2,
        );
        expect(
          (await retry
                  .customSelect('SELECT sum(amount) AS total FROM legs')
                  .get())
              .single
              .read<int>('total'),
          11500,
        );
        expect(
          await retry.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await retry.close();
      }
    });
  }
}
