import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'places.dart';

/// Every text on screen, rich ones read out whole.
List<String> _texts(WidgetTester tester) => [
  for (final w in tester.widgetList<RichText>(find.byType(RichText)))
    w.text.toPlainText(),
];

/// On a form whose amount stands beside its currency, an account in
/// another currency shows that currency once: the forms once read
/// 「USD USD 0.00」.
void main() {
  Ledger book() => demoLedger()
    ..accountCommands.addAccount(
      const Account('us', '美元', AccountKind.bank, 0, currency: 'USD'),
    );

  testWidgets('記一筆 names a foreign currency once', (tester) async {
    await show(tester, 360, 1, book: book());
    await go(tester, ['~記一筆', '^日常銀行']);
    await go(tester, ['^美元']);
    final texts = _texts(tester);
    expect(texts, contains('USD'));
    expect(texts, contains('0.00'));
    expect(texts.where((t) => t.contains('USD')), ['USD']);
  });

  testWidgets('a recurring item names a foreign currency once', (tester) async {
    await show(tester, 360, 1, book: book());
    await go(tester, ['更多', '定期交易', '~管理', 'Netflix']);
    await go(tester, ['^帳戶']);
    await go(tester, ['^美元']);
    final texts = _texts(tester);
    expect(texts, contains('USD 0.00'));
    expect(texts.where((t) => t.contains('USD')), ['USD 0.00']);
  });
}
