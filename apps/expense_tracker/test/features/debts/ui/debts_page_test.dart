import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';
import '../../../support/seeded_book.dart' show emptyBook;

/// 代墊與借貸's loan card: its ring is read as 已還 and a percent, and the
/// card as its name, what was borrowed, what is owed and that share
/// (review 16: progress semantics, the loan ring).
void main() {
  testWidgets('a loan\'s ring is read as 已還 N%, as the card says it', (
    tester,
  ) async {
    final ledger = emptyBook()
      ..accountCommands.addAccount(
        const Account(
          'loan',
          '車貸',
          AccountKind.loan,
          -300000,
          principal: 400000,
        ),
      );
    await show(tester, 360, 1, height: 800, book: ledger);
    await go(tester, ['更多', '代墊與借貸']);
    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    // 400,000 borrowed, 300,000 owed: 100,000 / 400,000 = 25% paid.
    expect((ring.semanticsLabel, ring.semanticsValue), ('已還', '25%'));
    expect(
      find.bySemanticsLabel(RegExp('^車貸，原借 400,000，尚欠 300,000，已還 25%')),
      findsOneWidget,
    );
  });
}
