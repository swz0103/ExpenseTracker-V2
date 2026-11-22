import 'package:expense_tracker/src/app/load_failed_page.dart';
import 'package:flutter/material.dart';
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
    await tester.tap(find.text('再試一次'));
    await tester.tap(find.text('從備份還原'));
    await tester.tap(find.text('匯出診斷'));
    expect(pressed, ['retry', 'restore', 'export']);
  });
}
