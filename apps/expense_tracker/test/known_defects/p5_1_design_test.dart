// Work package 5.1: words that can be pressed read clearly.
import 'package:expense_tracker/src/core/design_system/components.dart';
import 'package:expense_tracker/src/features/entries/forms/compose_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'known_defect.dart';

void main() {
  testWidgets('DSN-01: the 收入 and 轉帳 tabs of 記一筆 read at 4.5:1 on white', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntryTypeTabs(
            labels: const ['支出', '收入', '轉帳'],
            selected: 0,
            color: Colors.red,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    for (final label in ['收入', '轉帳']) {
      final colour = tester.widget<Text>(find.text(label)).style!.color!;
      expect(
        contrastOf(colour, const Color(0xFFFFFFFF)),
        greaterThanOrEqualTo(4.5),
        reason: '$label tab',
      );
    }
  }, skip: knownDefect('DSN-01', '5.1') != null);
}
