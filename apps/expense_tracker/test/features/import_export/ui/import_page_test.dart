import 'package:expense_tracker/src/app/demo/seed.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

/// D82: an import is not asked about first; the note says how many came
/// in, and its 復原 takes all of it back, the accounts and categories it
/// added with it.
void main() {
  const csv =
      '日期,類型,金額,帳戶,分類,商家,標籤,備註\n'
      '2026-10-01,支出,120,隨身現金,飲食日常,早餐店,家用,蛋餅\n'
      '2026-10-01,收入,500,新的帳戶,新的分類,,,紅包\n';

  testWidgets('匯入 adds at once; 復原 takes it all back', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, Object?>{'text': csv}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final ledger = demoLedger();
    final entries = ledger.entries.length;
    final accounts = ledger.accounts.all.length;
    final categories = ledger.categories.all.length;
    await show(tester, 360, 1, book: ledger);
    await go(tester, ['更多', '設定', '匯入與匯出', 'CSV 檔案', '貼上', '匯入 2 筆']);
    expect(ledger.entries.length, entries + 2);
    expect(ledger.accounts.all, hasLength(accounts + 1));
    expect(find.text('已匯入 2 筆紀錄'), findsOneWidget);
    await tester.tap(find.byKey(Keys.snack('復原')));
    await tester.pumpAndSettle();
    expect(ledger.entries.length, entries);
    expect(ledger.accounts.all, hasLength(accounts));
    expect(ledger.categories.all, hasLength(categories));
    expect(ledger.trash.all, isEmpty);
  });
}
