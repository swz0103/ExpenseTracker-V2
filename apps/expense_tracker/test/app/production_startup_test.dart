import 'dart:io';

import 'package:expense_tracker/src/app/production_startup.dart';
import 'package:expense_tracker/src/core/platform/startup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the production composition starts at setup in an empty folder', () {
    final directory = Directory.systemTemp.createTempSync('production-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final startup = productionStartup(directory);
    expect(startup.state, isA<NeedsSetup>());
    expect(startup.directory.path, directory.path);
  });

  test('a desktop development build keeps the ledger in the home '
      'folder', () async {
    final home = Platform.isWindows
        ? Platform.environment['APPDATA']
        : Platform.environment['HOME'];
    if (Platform.isAndroid || Platform.isIOS || home == null) return;
    expect((await applicationDirectory()).path, '$home/.expense_tracker_v2');
  });
}
