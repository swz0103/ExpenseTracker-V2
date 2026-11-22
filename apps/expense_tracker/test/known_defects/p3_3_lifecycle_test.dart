// Work package 3.3: what runs when the app leaves the screen.
import 'dart:io';

import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/backup/model/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'known_defect.dart';

void main() {
  test(
    'ARC-05: hidden then paused in one tick make one backup, not two',
    () async {
      final directory = Directory.systemTemp.createTempSync('p3-4-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final preferences = Preferences()
        ..phoneFolderSet('content://tree/backups', name: 'x');
      var written = 0;
      final box = Outbox(
        directory,
        preferences,
        write: (folder, {withPhotos = true}) async {
          folder.createSync(recursive: true);
          written++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return File('${folder.path}/b-$written.etbk')..writeAsStringSync('x');
        },
        revision: () => 1,
        ledger: 'l',
        schedule: ({required on}) =>
            Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      // The app calls prepare() for hidden and again for paused.
      await Future.wait([box.prepare(), box.prepare()]);
      expect(written, 1);
    },
    skip: knownDefect('ARC-05', '3.3'),
  );
}
