import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app and its Android side talk over one channel by method name
/// (lib/src/app/android/channel.dart, MainActivity.kt and its parts). A
/// name typed differently on one side fails only on a phone, so each name
/// the app calls must be one the Android side answers, and each the
/// Android side sends must be one the app listens for.
void main() {
  String all(String folder, String suffix) => [
    for (final entity in Directory(folder).listSync(recursive: true))
      if (entity is File && entity.path.endsWith(suffix))
        entity.readAsStringSync(),
  ].join('\n');

  Set<String> found(String text, List<String> patterns) => {
    for (final pattern in patterns)
      for (final match in RegExp(pattern).allMatches(text)) match[1]!,
  };

  final dart = all('lib', '.dart');
  final kotlin = all('android/app/src/main/kotlin', '.kt');

  test('every method the app calls is answered on Android', () {
    final called = found(dart, [
      r"invoke(?:List|Map)?Method(?:<[^(]*?>)?\(\s*'(\w+)'",
      // keystore.dart's own wrapper around the channel.
      r"_call\(\s*'(\w+)'",
    ]);
    final answered = found(kotlin, [
      r'"(\w+)"\s*->',
      r'call\.method\s*[!=]=\s*"(\w+)"',
    ]);
    expect(called, isNotEmpty);
    expect(called.difference(answered), isEmpty);
  });

  test('every method Android sends is listened for in the app', () {
    final sent = found(kotlin, [r'invokeMethod\(\s*"(\w+)"']);
    final heard = found(dart, [r"call\.method\s*==\s*'(\w+)'"]);
    expect(sent, isNotEmpty);
    expect(sent.difference(heard), isEmpty);
  });
}
