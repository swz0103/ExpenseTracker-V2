import 'dart:io';

import 'package:expense_tracker/src/app/upgrade_held_page.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/ledger/persistence/upgrade_backup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// D19: a book whose copy before the upgrade could not be kept is held
/// back, and the page says why and offers each way on; going on without
/// the copy asks a second time.
void main() {
  final full = UpgradeBackupFailed.of(
    const FileSystemException(
      'write failed',
      'backups/before-upgrade.etbk',
      OSError('No space left on device', 28),
    ),
  );

  Future<List<String>> open(
    WidgetTester tester,
    UpgradeBackupFailed failure,
  ) async {
    final pressed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: UpgradeHeldPage(
          failure: failure,
          onRetry: () => pressed.add('retry'),
          onExport: () => pressed.add('export'),
          onWithoutBackup: () => pressed.add('without'),
        ),
      ),
    );
    return pressed;
  }

  testWidgets('a full disk is said in words, with how to make room', (
    tester,
  ) async {
    await open(tester, full);
    expect(find.text('升級前的備份沒有完成'), findsOneWidget);
    expect(find.text('手機空間不足，無法先把帳本備份起來。帳本沒有被改動，也還沒有升級到這個版本。'), findsOneWidget);
    expect(
      find.text(
        '升級前會先完整備份一份帳本（含收據照片），手機需要有足夠的空間。'
        '可以先刪除不需要的照片、影片或 App，再按「再試一次」。',
      ),
      findsOneWidget,
    );
  });

  testWidgets('another failure is said with its reason', (tester) async {
    await open(
      tester,
      UpgradeBackupFailed.of(const FileSystemException('denied', 'backups')),
    );
    expect(find.textContaining('無法先把帳本備份起來（'), findsOneWidget);
  });

  testWidgets('retry and export do what they say', (tester) async {
    final pressed = await open(tester, full);
    await tester.tap(find.byKey(Keys.upgradeHeld('retry')));
    await tester.tap(find.byKey(Keys.upgradeHeld('export')));
    expect(pressed, ['retry', 'export']);
  });

  testWidgets('going on without the copy asks twice', (tester) async {
    final pressed = await open(tester, full);
    expect(find.text('不備份，仍要升級'), findsOneWidget);
    // Asked, then not confirmed: nothing happens.
    await tester.tap(find.byKey(Keys.upgradeHeld('skip')));
    await tester.pumpAndSettle();
    expect(find.text('確定不備份就升級？'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('確定不備份就升級？'), findsNothing);
    expect(pressed, isEmpty);
    // Asked again and confirmed.
    await tester.tap(find.byKey(Keys.upgradeHeld('skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(pressed, ['without']);
  });

  test('the hold stays until the copy is kept, or the person goes on '
      'without it', () async {
    final hold = UpgradeHold();
    final asked = <bool>[];
    var told = 0;
    hold.addListener(() => told++);
    final preparing = hold.prepare(({withoutBackup = false}) async {
      asked.add(withoutBackup);
      return withoutBackup ? null : full;
    });
    await Future<void>.delayed(Duration.zero);
    expect(hold.held, same(full));
    // Tried again: still no copy, still held.
    hold.choose(withoutBackup: false);
    await Future<void>.delayed(Duration.zero);
    expect(hold.held, same(full));
    // On without it.
    hold.choose(withoutBackup: true);
    await preparing;
    expect(hold.held, isNull);
    expect(asked, [false, false, true]);
    // Held, freed, held, freed.
    expect(told, 4);
    // Nothing held: a choice does nothing.
    hold.choose(withoutBackup: true);
  });
}
