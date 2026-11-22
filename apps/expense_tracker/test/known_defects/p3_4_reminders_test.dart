// Work packages 3.3 and 3.4: reminders and background work agree with the
// ledger.
import 'dart:io';

import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/platform/preferences.dart';
import 'package:expense_tracker/src/features/backup/model/outbox.dart';
import 'package:expense_tracker/src/features/reminders/ui/reminders_section.dart'
    show reminderBookOf;
import 'package:flutter_test/flutter_test.dart';

import '../baseline/baseline_ledger.dart';
import 'known_defect.dart';

void main() {
  test('REM-05: a day let go of is not reminded about', () {
    final gym = Recurring(
      id: 'gym',
      name: '健身房',
      amount: 1200,
      day: 25,
      account: 'bank',
      category: '飲食',
      start: day(2026, 1, 25),
      skipped: {day(2026, 11, 25)},
    );
    final ledger = ledgerOf(
      today: day(2026, 11, 22),
      accounts: const [Account('bank', '銀行', AccountKind.bank, 100000)],
      recurring: [gym],
    );
    final reminders = reminderBookOf(ledger).reminders();
    // Nov 25 was skipped: no reminder is made for it.
    expect([
      for (final r in reminders)
        if (r.title.contains('健身房') && r.day == day(2026, 11, 25)) r,
    ], isEmpty);
  }, skip: knownDefect('REM-05', '3.4'));

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
