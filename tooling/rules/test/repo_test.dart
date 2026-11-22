import 'dart:io';

import 'package:rules/src/cli.dart';
import 'package:test/test.dart';

void main() {
  test('the real repository holds the committed baseline', () {
    final root = findRoot(Directory.current.path);
    final out = StringBuffer(), err = StringBuffer();
    final code = runCheck(const [], root: root, out: out, err: err);
    expect(code, 0, reason: err.toString());
  }, timeout: const Timeout(Duration(minutes: 3)));
}
