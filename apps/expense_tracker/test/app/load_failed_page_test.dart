import 'package:expense_tracker/src/app/load_failed_page.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A book that cannot be opened is never a dead end: the page offers to
/// try again, to restore a backup and to export what went wrong.
void main() {
  testWidgets('each way out is offered and does what it says', (tester) async {
    final pressed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LoadFailedPage(
          onRetry: () => pressed.add('retry'),
          onRestore: () => pressed.add('restore'),
          onExport: () => pressed.add('export'),
        ),
      ),
    );
    expect(find.text('帳本打不開'), findsOneWidget);
    await tester.tap(find.byKey(Keys.loadFailed('retry')));
    await tester.tap(find.byKey(Keys.loadFailed('restore')));
    expect(find.text('從備份還原'), findsOneWidget);
    await tester.tap(find.byKey(Keys.loadFailed('export')));
    expect(pressed, ['retry', 'restore', 'export']);
  });

  testWidgets('a damaged file says so, offers a restore and copies the '
      'diagnostics (D94)', (tester) async {
    final pressed = <String>[];
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DamagedBookPage(
          onRetry: () => pressed.add('retry'),
          onRestore: () => pressed.add('restore'),
        ),
      ),
    );
    expect(find.text('帳本檔案損毀'), findsOneWidget);
    expect(find.textContaining('不是密碼錯誤'), findsOneWidget);
    expect(find.textContaining('沒有建立新的空帳本'), findsOneWidget);
    await tester.tap(find.byKey(Keys.loadFailed('retry')));
    await tester.tap(find.byKey(Keys.loadFailed('restore')));
    expect(pressed, ['retry', 'restore']);
    await tester.tap(find.byKey(Keys.loadFailed('export')));
    await tester.pump();
    expect(copied, isNotNull);
    expect(find.text('已複製診斷資料'), findsOneWidget);
  });
}
