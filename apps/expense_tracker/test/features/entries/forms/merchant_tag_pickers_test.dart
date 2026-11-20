import 'package:expense_tracker/src/features/entries/forms/merchant_tag_pickers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/places.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget picker) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: picker)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('MerchantPicker', () {
    late List<String> done;
    setUp(() => done = []);

    Widget picker({String initial = ''}) => MerchantPicker(
      known: const ['全聯', '全家', '好市多'],
      initial: initial,
      onDone: done.add,
    );

    testWidgets('typing narrows the names used before', (tester) async {
      await show(tester, picker());
      expect(find.text('好市多'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '全');
      await tester.pump();
      expect(find.text('全聯'), findsOneWidget);
      expect(find.text('全家'), findsOneWidget);
      expect(find.text('好市多'), findsNothing);
      await go(tester, ['全家']);
      expect(done, ['全家']);
    });

    testWidgets('a new name can be added, typed or entered', (tester) async {
      await show(tester, picker());
      await tester.enterText(find.byType(TextField), ' 鼎泰豐 ');
      await tester.pump();
      await go(tester, ['新增「鼎泰豐」']);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(done, ['鼎泰豐', '鼎泰豐']);
    });

    testWidgets('a name already used is not offered as new', (tester) async {
      await show(tester, picker());
      await tester.enterText(find.byType(TextField), '全聯');
      await tester.pump();
      expect(find.text('新增「全聯」'), findsNothing);
    });

    testWidgets('不記商家 only when one was set, and clears it', (tester) async {
      await show(tester, picker());
      expect(find.text('不記商家'), findsNothing);
      await show(tester, picker(initial: '全聯'));
      await go(tester, ['不記商家']);
      expect(done, ['']);
    });
  });

  group('TagPicker', () {
    late List<List<String>> done;
    setUp(() => done = []);

    Widget picker({List<String> initial = const ['旅遊']}) => TagPicker(
      known: const ['旅遊', '家用'],
      initial: initial,
      onDone: (tags) => done.add([...tags]),
    );

    testWidgets('tags are picked and let go of, then kept with 完成', (
      tester,
    ) async {
      await show(tester, picker());
      await go(tester, ['#家用', '#旅遊', '完成']);
      expect(done.single, ['家用']);
    });

    testWidgets('a new tag is added once, without its #', (tester) async {
      await show(tester, picker(initial: const []));
      await tester.enterText(find.byType(TextField), '#聚餐');
      await go(tester, ['~加入']);
      await tester.enterText(find.byType(TextField), '聚餐');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(find.byType(TextField), '   ');
      await go(tester, ['~加入', '完成']);
      expect(done.single, ['聚餐']);
      expect(find.text('#聚餐'), findsOneWidget);
    });

    testWidgets('no more than sixteen tags', (tester) async {
      await show(tester, picker(initial: [for (var i = 0; i < 16; i++) 't$i']));
      await go(tester, ['#家用']);
      await tester.enterText(find.byType(TextField), '再一個');
      await go(tester, ['~加入', '完成']);
      expect(done.single, hasLength(16));
      expect(done.single, isNot(contains('家用')));
    });
  });
}
