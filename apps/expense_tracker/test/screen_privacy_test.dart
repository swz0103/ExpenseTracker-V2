import 'dart:io';

import 'package:expense_tracker/src/screen_privacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('screen hiding is kept and applied again at launch', () async {
    final directory = Directory.systemTemp.createTempSync('privacy-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final told = <bool>[];
    Future<void> secure(bool on) async => told.add(on);
    final privacy = ScreenPrivacy(directory, secure);
    expect(privacy.on, isFalse);
    await privacy.turn(on: true);
    expect(privacy.on, isTrue);
    // A new launch reads the kept choice.
    await ScreenPrivacy(directory, secure).apply();
    await privacy.turn(on: false);
    expect(privacy.on, isFalse);
    expect(told, [true, true, false]);
  });
}
