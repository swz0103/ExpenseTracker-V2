import 'package:expense_tracker/src/core/charts/treemap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/places.dart';
import '../../../../support/seeded_book.dart' show emptyBook;

/// 總覽's 財務分布: a part picked on the map is named with its whole
/// percent of the assets (review 16: percent call sites).
void main() {
  testWidgets('a part picked says its share of the assets', (tester) async {
    await show(tester, 360, 1, height: 1600, book: emptyBook());
    final map = find.byType(Treemap);
    await tester.ensureVisible(map);
    await tester.pumpAndSettle();
    // The dearest part is laid out first, at the top left.
    await tester.tapAt(tester.getTopLeft(map) + const Offset(8, 8));
    await tester.pumpAndSettle();
    // 銀行 200,000 and 美元戶 US$5,000 at 32, 160,000: 360,000 in the
    // bank; 現金 5,000; 365,000 in all. 360,000 / 365,000 = 98.6% → 99%.
    expect(find.text('銀行帳戶　99%'), findsOneWidget);
  });
}
