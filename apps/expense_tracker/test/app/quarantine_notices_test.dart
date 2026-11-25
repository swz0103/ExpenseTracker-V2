import 'dart:io';

import 'package:expense_tracker/src/app/quarantine_notices.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/ledger/persistence/quarantine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// D18: rows a newer version wrote are told once per distinct set, the
/// set's fingerprint kept beside the keyring; rows that cannot be read
/// are told every opening.
void main() {
  late Directory directory;
  late QuarantineNotices notices;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('quarantine-told-');
    notices = QuarantineNotices(File('${directory.path}/quarantine-told'));
  });
  tearDown(() => directory.deleteSync(recursive: true));

  const newer1 = QuarantinedRow(
    'entry',
    'e1',
    QuarantineReason.newer,
    version: 3,
  );
  const newer2 = QuarantinedRow(
    'entry',
    'e2',
    QuarantineReason.newer,
    version: 3,
  );
  const broken = QuarantinedRow('entry', 'e9', QuarantineReason.unreadable);

  test('a newer set is told once, then not while it stays the same', () async {
    expect(await notices.toTell([newer1, newer2]), [newer1, newer2]);
    expect(await notices.toTell([newer1, newer2]), isEmpty);
    // The same set in another order is the same set.
    expect(await notices.toTell([newer2, newer1]), isEmpty);
  });

  test('a set that changed is told again', () async {
    expect(await notices.toTell([newer1]), [newer1]);
    expect(await notices.toTell([newer1, newer2]), [newer1, newer2]);
    expect(await notices.toTell([newer1, newer2]), isEmpty);
  });

  test('rows that cannot be read are told every opening', () async {
    expect(await notices.toTell([broken, newer1]), [broken, newer1]);
    expect(await notices.toTell([broken, newer1]), [broken]);
    expect(await notices.toTell([broken, newer1]), [broken]);
  });

  test('the fingerprint holds no content, and goes with the set', () async {
    await notices.toTell([newer1, newer2]);
    // Two rows; the keys `entry/e1@3` and `entry/e2@3`, hashed.
    expect(notices.file.readAsStringSync(), newerFingerprint([newer1, newer2]));
    expect(notices.file.readAsStringSync(), startsWith('2:'));
    expect(notices.file.readAsStringSync(), isNot(contains('e1')));
    // No newer rows: nothing is remembered, and a set coming back is told.
    expect(await notices.toTell(const []), isEmpty);
    expect(notices.file.existsSync(), isFalse);
    expect(await notices.toTell([newer1, newer2]), [newer1, newer2]);
  });

  test('the fingerprint is FNV-1a of the sorted keys', () {
    // The keys sorted and joined, "entry/e1@3\nentry/e2@3": its 32-bit
    // FNV-1a is dae28938 (worked out apart from the app: h = 811c9dc5,
    // then per character h = (h xor c) * 16777619 mod 2^32).
    expect(newerFingerprint([newer2, newer1]), '2:dae28938');
  });

  testWidgets('the notice offers the report, a restore, or going on', (
    tester,
  ) async {
    final answers = <bool>[];
    var exported = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              await showQuarantineNotice(context, [
                newer1,
                broken,
              ], onExport: () => exported++),
            ),
            key: const ValueKey('test:open'),
            child: const Text('open'),
          ),
        ),
      ),
    );
    for (final choice in ['export', 'restore', 'continue']) {
      await tester.tap(find.byKey(const ValueKey('test:open')));
      await tester.pumpAndSettle();
      expect(find.text('有 2 筆資料讀不出來，已先隔離'), findsOneWidget);
      await tester.tap(find.byKey(Keys.quarantine(choice)));
      await tester.pumpAndSettle();
      if (choice == 'export') {
        // The report leaves the notice open.
        await tester.tap(find.byKey(Keys.quarantine('continue')));
        await tester.pumpAndSettle();
      }
    }
    expect(exported, 1);
    expect(answers, [false, true, false]);
  });
}
