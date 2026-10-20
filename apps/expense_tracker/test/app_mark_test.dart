import 'package:expense_tracker/src/look/app_mark.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the app mark paints at the size asked', (tester) async {
    await tester.pumpWidget(const Center(child: AppMark(size: 72)));
    expect(tester.getSize(find.byType(AppMark)), const Size(72, 72));
  });
}
