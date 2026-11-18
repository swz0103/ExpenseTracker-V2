import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/places.dart';

/// What 匯入 CSV shows once a text is pasted: how many were read, their
/// total, what the import adds, and each entry under its day, the
/// latest day first.
void main() {
  const csv =
      '日期,類型,金額,帳戶,分類,商家,標籤,備註\n'
      '2026-10-01,支出,120,隨身現金,飲食日常,早餐店,家用,蛋餅\n'
      '2026-10-03,支出,80,隨身現金,飲食日常,咖啡,,拿鐵\n'
      '2026-10-01,收入,500,不存在的帳戶,新的分類,,,紅包\n'
      '壞掉的一行\n';

  testWidgets('a pasted text is shown before it is imported', (tester) async {
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
    await show(tester, 360, 1);
    await go(tester, ['更多', '設定', '匯入與匯出', 'CSV 檔案', '貼上']);

    expect(find.text('3 筆'), findsOneWidget);
    expect(find.text('合計 700'), findsOneWidget);
    expect(find.text('略過 1 行 ⓘ'), findsOneWidget);
    expect(find.text('＋ 新的分類'), findsOneWidget);
    // The days, the latest first.
    final days = [
      for (final t in tester.widgetList<Text>(
        find.textContaining(RegExp(r'^10/\d 週')),
      ))
        t.data,
    ];
    expect(days, ['10/3 週六', '10/1 週四']);
  });
}
