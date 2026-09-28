import 'dart:convert';

import 'package:expense_preview/app_pin.dart';
import 'package:flutter_test/flutter_test.dart';

final class _MemoryRecord implements PinRecordStore {
  String? value;
  bool failWrite = false;

  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    if (failWrite) throw StateError('storage unavailable');
    value = next;
  }

  @override
  Future<void> delete() async => value = null;
}

void main() {
  test(
    'PIN verifier stores only a salted derived value and can be revoked',
    () async {
      final record = _MemoryRecord();
      final store = VerifiedAppPinStore(record);
      expect(await store.isEnabled(), isFalse);
      await expectLater(store.enable('12345'), throwsFormatException);
      await expectLater(store.enable('1234567890123'), throwsFormatException);
      await expectLater(store.enable('12345x'), throwsFormatException);
      expect(record.value, isNull);
      await store.enable('123456');
      final data = jsonDecode(record.value!) as Map<String, dynamic>;
      expect(data.keys.toSet(), {
        'version',
        'iterations',
        'salt',
        'hash',
        'failures',
      });
      expect(await store.matches('000000'), isFalse);
      expect(await store.matches('123456'), isTrue);
      expect((jsonDecode(record.value!) as Map)['failures'], 0);
      await expectLater(store.enable('654321'), throwsStateError);
      await store.disable();
      expect(await store.isEnabled(), isFalse);
      expect(await store.matches('123456'), isFalse);
    },
  );

  test('malformed or altered verifier fails closed', () async {
    final record = _MemoryRecord();
    final store = VerifiedAppPinStore(record);
    await store.enable('678901');
    final saved = record.value!;
    final data = jsonDecode(saved) as Map<String, dynamic>;
    data['hash'] = base64Encode(List<int>.filled(32, 0));
    record.value = jsonEncode(data);
    expect(await store.matches('678901'), isFalse);
    record.value = '{broken';
    expect(await store.isEnabled(), isTrue);
    expect(await store.matches('678901'), isFalse);
    record.value = saved;
    expect(await store.matches('678901'), isTrue);
  });

  test('failed secure-store write never enables PIN', () async {
    final record = _MemoryRecord()..failWrite = true;
    final store = VerifiedAppPinStore(record);
    await expectLater(store.enable('123456'), throwsStateError);
    expect(await store.isEnabled(), isFalse);
  });

  test('five failed attempts require master-password recovery', () async {
    final record = _MemoryRecord();
    final store = VerifiedAppPinStore(record);
    await store.enable('123456');
    for (var i = 1; i <= 5; i++) {
      expect(await store.matches('1'), isFalse);
      expect((jsonDecode(record.value!) as Map)['failures'], i);
    }
    expect(await store.matches('123456'), isFalse);
    await store.disable();
    expect(await store.isEnabled(), isFalse);
  });
}
