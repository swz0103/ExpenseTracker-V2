import 'dart:io';

import 'package:expense_tracker/src/features/lock/model/picked_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the copy of a chosen backup is deleted, and one gone already '
      'is nothing to do', () {
    final folder = Directory.systemTemp.createTempSync('picked');
    addTearDown(() => folder.deleteSync(recursive: true));
    final copy = File('${folder.path}/chosen.etbk')..writeAsStringSync('x');

    forgetPickedCopy(copy.path);
    expect(copy.existsSync(), isFalse);
    forgetPickedCopy(copy.path);
    expect(copy.existsSync(), isFalse);
  });
}
