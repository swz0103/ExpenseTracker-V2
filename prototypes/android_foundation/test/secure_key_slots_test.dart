import 'dart:async';
import 'dart:convert';

import 'package:android_foundation/key_access.dart';
import 'package:android_foundation/secure_key_slots.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundation_values/foundation_values.dart';

final class MemorySlots implements SlotVault {
  final values = <String, String>{};
  var writes = 0;
  var failRead = false;
  var writeMode = 'normal';
  Completer<void>? gate;
  @override
  Future<String?> read(String slot) async {
    await gate?.future;
    if (failRead) throw StateError('sensitive fixture exception');
    return values[slot];
  }

  @override
  Future<void> write(String slot, String value) async {
    writes++;
    if (writeMode == 'before') throw StateError('sensitive fixture exception');
    if (writeMode != 'discard') values[slot] = value;
    if (writeMode == 'after') throw StateError('sensitive fixture exception');
  }
}

void main() {
  test(
    'independent slots persist and fresh adapter reads without rewriting',
    () async {
      final vault = MemorySlots();
      final first = PublicId.generate();
      final second = PublicId.generate();
      await SecureKeySlots(vault).create(first);
      final original = vault.values[first.value];
      await SecureKeySlots(vault).create(second);
      expect(vault.values[first.value], original);
      expect(vault.values[second.value], isNot(original));
      expect(base64Decode(original!.substring(3)), hasLength(32));
      expect(
        (await SecureKeySlots(vault).read(first)).toString(),
        'StorageKey(redacted)',
      );
      await SecureKeySlots(vault).read(second);
      expect(vault.writes, 2);
    },
  );
  for (final value in [
    null,
    'v2:future',
    'v1:bad',
    'v1:${base64Encode(List.filled(31, 1))}',
  ]) {
    test('missing or unknown slot $value fails without repair', () async {
      final vault = MemorySlots();
      final slot = PublicId.generate();
      if (value != null) vault.values[slot.value] = value;
      await expectLater(
        SecureKeySlots(vault).read(slot),
        throwsA(isA<KeyUnavailable>()),
      );
      expect(vault.values[slot.value], value);
      expect(vault.writes, 0);
    });
  }
  test(
    'existing slot cannot be replaced even if its encoding is unknown',
    () async {
      final vault = MemorySlots();
      final slot = PublicId.generate();
      vault.values[slot.value] = 'v2:future';
      await expectLater(
        SecureKeySlots(vault).create(slot),
        throwsA(isA<KeyUnavailable>()),
      );
      expect(vault.values[slot.value], 'v2:future');
      expect(vault.writes, 0);
    },
  );
  for (final mode in ['before', 'after', 'discard']) {
    test(
      'ambiguous vault write $mode fails and retains existing slots',
      () async {
        final vault = MemorySlots();
        final retained = PublicId.generate();
        await SecureKeySlots(vault).create(retained);
        final original = vault.values[retained.value];
        final slot = PublicId.generate();
        vault.writeMode = mode;
        await expectLater(
          SecureKeySlots(vault).create(slot),
          throwsA(isA<KeyUnavailable>()),
        );
        expect(vault.values[retained.value], original);
        if (mode == 'after') {
          await SecureKeySlots(vault).read(slot);
          final count = vault.writes;
          await expectLater(
            SecureKeySlots(vault).create(slot),
            throwsA(isA<KeyUnavailable>()),
          );
          expect(vault.writes, count);
        }
      },
    );
  }
  test('read failure is sanitized and guard releases for retry', () async {
    final vault = MemorySlots()..failRead = true;
    final slot = PublicId.generate();
    await expectLater(
      SecureKeySlots(vault).create(slot),
      throwsA(predicate((e) => e.toString() == 'KeyUnavailable')),
    );
    expect(vault.writes, 0);
    vault.failRead = false;
    await SecureKeySlots(vault).create(slot);
    expect(vault.writes, 1);
  });
  test('two adapter instances cannot overlap creating the same slot', () async {
    final vault = MemorySlots()..gate = Completer<void>();
    final slot = PublicId.generate();
    final first = SecureKeySlots(vault).create(slot);
    await expectLater(
      SecureKeySlots(vault).create(slot),
      throwsA(isA<KeyUnavailable>()),
    );
    vault.gate!.complete();
    await first;
    expect(vault.writes, 1);
  });
}
