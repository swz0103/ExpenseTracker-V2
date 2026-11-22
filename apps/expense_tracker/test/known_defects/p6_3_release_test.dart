// Work package 6.3: what the Play build may ask for.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'known_defect.dart';

void main() {
  test('AND-01: the main manifest does not ask to install packages', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    // Self-update (REQUEST_INSTALL_PACKAGES) belongs to a sideload-only
    // build variant, not to the manifest every variant shares.
    expect(
      manifest.readAsStringSync(),
      isNot(contains('android.permission.REQUEST_INSTALL_PACKAGES')),
    );
  }, skip: knownDefect('AND-01', '6.3'));
}
