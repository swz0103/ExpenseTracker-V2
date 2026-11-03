import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android shows nothing of its own before the opening animation: the
/// start screen is the app's paper colour with no icon, on every version
/// and in both themes, so the animation seems to be the first thing shown.
void main() {
  const res = 'android/app/src/main/res';

  for (final dir in ['drawable', 'drawable-v21']) {
    test('$dir/launch_background is the paper colour alone', () {
      final text = File('$res/$dir/launch_background.xml').readAsStringSync();
      expect(text, contains('@color/launch_background'));
      expect(text.contains('<bitmap'), isFalse);
      expect(text.contains('ic_launcher'), isFalse);
    });
  }

  for (final dir in ['values-v31', 'values-night-v31']) {
    test('$dir: the Android 12 start screen has no icon', () {
      final text = File('$res/$dir/styles.xml').readAsStringSync();
      expect(
        text,
        contains(
          '<item name="android:windowSplashScreenBackground">'
          '@color/launch_background</item>',
        ),
      );
      expect(
        text,
        contains(
          '<item name="android:windowSplashScreenAnimatedIcon">'
          '@android:color/transparent</item>',
        ),
      );
    });
  }

  for (final dir in ['values', 'values-night', 'values-v31', 'values-night-v31']) {
    test('$dir: nothing flashes between the start and the first frame', () {
      final text = File('$res/$dir/styles.xml').readAsStringSync();
      final normal = text.substring(text.indexOf('name="NormalTheme"'));
      expect(
        normal,
        contains(
          '<item name="android:windowBackground">'
          '@color/launch_background</item>',
        ),
      );
    });
  }
}
