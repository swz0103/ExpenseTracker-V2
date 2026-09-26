import 'dart:convert';

import 'package:android_foundation/key_access.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryVault implements KeyVault {
  String? value;
  int writes = 0;
  bool failRead = false;
  bool discardWrite = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('fixture error');
    return value;
  }

  @override
  Future<void> write(String input) async {
    writes++;
    if (!discardWrite) value = input;
  }
}

void main() {
  test(
    'existing database with missing key fails without writing a replacement',
    () async {
      final vault = MemoryVault();
      await expectLater(
        KeyAccess(vault).load(databaseExists: () async => true),
        throwsA(isA<KeyUnavailable>()),
      );
      expect(vault.writes, 0);
    },
  );
  test('concurrent first opens share one verified key creation', () async {
    final vault = MemoryVault();
    final access = KeyAccess(vault);
    final keys = await Future.wait([
      access.load(databaseExists: () async => false),
      access.load(databaseExists: () async => false),
    ]);
    expect(identical(keys[0], keys[1]), isTrue);
    expect(vault.writes, 1);
    expect(base64Decode(vault.value!.substring(3)), hasLength(32));
  });
  test('stored valid key is reused without writing', () async {
    final vault = MemoryVault()
      ..value = 'v1:${base64Encode(List.filled(32, 1))}';
    await KeyAccess(vault).load(databaseExists: () async => true);
    expect(vault.writes, 0);
  });
  test(
    'invalid or future key encoding does not overwrite stored material',
    () async {
      for (final value in [
        'v2:future',
        'v1:bad',
        'v1:${base64Encode(List.filled(31, 1))}',
      ]) {
        final vault = MemoryVault()..value = value;
        await expectLater(
          KeyAccess(vault).load(databaseExists: () async => true),
          throwsA(isA<KeyUnavailable>()),
        );
        expect(vault.value, value);
        expect(vault.writes, 0);
      }
    },
  );
  test('vault read error fails closed and can retry without reset', () async {
    final vault = MemoryVault()..failRead = true;
    final access = KeyAccess(vault);
    await expectLater(
      access.load(databaseExists: () async => false),
      throwsA(isA<KeyUnavailable>()),
    );
    expect(vault.writes, 0);
    vault.failRead = false;
    await access.load(databaseExists: () async => false);
    expect(vault.writes, 1);
  });
  test('write that cannot be read back never returns a usable key', () async {
    final vault = MemoryVault()..discardWrite = true;
    await expectLater(
      KeyAccess(vault).load(databaseExists: () async => false),
      throwsA(isA<KeyUnavailable>()),
    );
    expect(vault.writes, 1);
  });
}
