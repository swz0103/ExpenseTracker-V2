import 'package:expense_tracker/src/core/ledger/ledger.dart';
import 'package:expense_tracker/src/core/look/glyphs.dart';
import 'package:expense_tracker/src/core/look/icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every mark draws', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Wrap(
          children: [
            for (final glyph in Glyph.values) GlyphIcon(glyph, size: 20),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('account marks are their own, and earlier ones still show', () {
    final categoryMarks = {
      for (final (_, keys) in categoryIconGroups) ...keys,
    };
    final keys = [
      for (final (_, marks) in accountIconGroups)
        for (final (key, _) in marks) key,
    ];
    expect(keys.length, 32);
    expect(keys.toSet().length, 32);
    for (final key in keys) {
      expect(categoryMarks, isNot(contains(key)), reason: key);
      expect(iconFor(key).name, key);
    }
    for (final kind in AccountKind.values) {
      for (final key in usualAccountIcons(kind)) {
        expect(keys, contains(key));
      }
    }
    const kept = Account('a', '舊帳戶', AccountKind.wallet, 0, icon: 'chat');
    expect(accountIcon(kept), Glyph.phonePay);
    const unknown = Account('b', '帳戶', AccountKind.bank, 0, icon: 'nothing');
    expect(accountIcon(unknown), Glyph.bank);
  });
}
