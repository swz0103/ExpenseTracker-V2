import 'dart:io';

import 'package:expense_tracker/src/core/platform/screen_privacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late List<bool> told;
  Future<void> secure(bool on) async => told.add(on);

  setUp(() {
    directory = Directory.systemTemp.createTempSync('privacy-');
    told = [];
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('at launch the screens are hidden, whatever the choice: the lock '
      'screen is what shows', () async {
    final privacy = ScreenPrivacy(directory, secure);
    expect(privacy.on, isFalse);
    expect(privacy.hiding, isTrue);
    await privacy.apply();
    expect(told, [true]);
  });

  test('with the choice off, an open ledger is shown and the lock screen '
      'hidden again (SEC-08)', () async {
    final privacy = ScreenPrivacy(directory, secure);
    await privacy.showing(locked: false);
    expect(privacy.hiding, isFalse);
    await privacy.showing(locked: true);
    expect(privacy.hiding, isTrue);
    expect(told, [false, true]);
  });

  test('with the choice on, the open ledger is hidden too', () async {
    final privacy = ScreenPrivacy(directory, secure);
    await privacy.showing(locked: false);
    await privacy.turn(on: true);
    expect(privacy.on, isTrue);
    expect(privacy.hiding, isTrue);
    await privacy.showing(locked: true);
    await privacy.showing(locked: false);
    await privacy.turn(on: false);
    expect(privacy.hiding, isFalse);
    expect(told, [false, true, true, true, false]);
  });

  test('the choice is kept beside the ledger for the next launch', () async {
    await ScreenPrivacy(directory, secure).turn(on: true);
    final next = ScreenPrivacy(directory, secure);
    expect(next.on, isTrue);
    await next.showing(locked: false);
    expect(next.hiding, isTrue);
    await next.turn(on: false);
    expect(ScreenPrivacy(directory, secure).on, isFalse);
  });

  test(
    'turning it off while the lock screen shows keeps that hidden',
    () async {
      final privacy = ScreenPrivacy(directory, secure);
      await privacy.turn(on: true);
      await privacy.turn(on: false);
      expect(told, [true, true]);
    },
  );

  test(
    'in memory, as in the preview, the choice holds for the visit',
    () async {
      final privacy = ScreenPrivacy.inMemory();
      expect(privacy.on, isFalse);
      await privacy.turn(on: true);
      expect(privacy.on, isTrue);
      await privacy.showing(locked: false);
      expect(privacy.hiding, isTrue);
      await privacy.turn(on: false);
      expect(privacy.hiding, isFalse);
    },
  );
}
