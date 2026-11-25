// Work package 6.3: what the Play build may ask for.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const permission = 'android.permission.REQUEST_INSTALL_PACKAGES';

  test('AND-01: the main manifest does not ask to install packages', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    // Self-update (REQUEST_INSTALL_PACKAGES) belongs to a sideload-only
    // build flavor, not to the manifest every flavor shares.
    expect(manifest.readAsStringSync(), isNot(contains(permission)));
  });

  test('AND-01: only the sideload flavor asks to install packages', () {
    final sideload = File('android/app/src/sideload/AndroidManifest.xml');
    expect(sideload.readAsStringSync(), contains(permission));
    final play = File('android/app/src/play/AndroidManifest.xml');
    // The play flavor has no manifest of its own to add it with.
    expect(
      play.existsSync() && play.readAsStringSync().contains(permission),
      isFalse,
    );
  });
}
