import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/features/backup/model/drive_backup.dart';
import 'package:expense_tracker/src/features/backup/model/old_key_backups.dart';
import 'package:expense_tracker/src/features/backup/ui/old_key_backups_offer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// D15: after a reset, the backups of the old keys are listed with their
/// dates and taken away only once confirmed.
void main() {
  late List<String> trashed;

  OldKeyBackups old(List<DriveFile> files, {bool unreached = false}) =>
      OldKeyBackups(
        epoch: 2,
        localBackups: () async => const [],
        driveFiles: () async {
          if (unreached) throw StateError('offline');
          return files;
        },
        trashOnDrive: (id) async => trashed.add(id),
      );

  setUp(() => trashed = []);

  Future<void> offer(WidgetTester tester, OldKeyBackups old) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => offerToRemoveOldKeyBackups(context, old),
              key: const ValueKey('test:reset'),
              child: const Text('reset'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('test:reset')));
    await tester.pumpAndSettle();
  }

  final files = [
    DriveFile('a', 'a.etbk', DateTime(2026, 11, 20, 12), 1, epoch: '1'),
    DriveFile('b', 'b.etbk', DateTime(2026, 11, 13, 12), 1),
  ];

  testWidgets('listed with how many and when; taken away once confirmed', (
    tester,
  ) async {
    await offer(tester, old(files));
    expect(find.text('刪除舊金鑰的備份？'), findsOneWidget);
    expect(
      find.textContaining('Google 雲端硬碟：2 份（2026/11/20、2026/11/13）'),
      findsOneWidget,
    );
    expect(trashed, isEmpty);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(trashed, ['a', 'b']);
    expect(find.text('已刪除 2 份舊金鑰的備份'), findsOneWidget);
  });

  testWidgets('turned down: nothing goes', (tester) async {
    await offer(tester, old(files));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(trashed, isEmpty);
  });

  testWidgets('none found: nothing asked; Drive not answering is said', (
    tester,
  ) async {
    await offer(tester, old(const []));
    expect(find.text('刪除舊金鑰的備份？'), findsNothing);
    await offer(tester, old(const [], unreached: true));
    expect(find.text('刪除舊金鑰的備份？'), findsNothing);
    expect(find.text('連不上 Google 雲端硬碟，那裡的舊備份沒有列出，可以之後自行刪除。'), findsOneWidget);
  });
}
