import 'package:expense_tracker/src/core/design_system/dialogs.dart';
import 'package:expense_tracker/src/core/design_system/keys.dart';
import 'package:expense_tracker/src/core/design_system/theme.dart';
import 'package:expense_tracker/src/core/formatting/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/android_text_scale.dart';
import '../../support/places.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);

  /// A page whose button asks [confirm] with a long body, answering into
  /// [answers].
  Widget page(List<bool> answers) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const AndroidTextScaler200()),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            key: const ValueKey('ask'),
            onPressed: () async => answers.add(
              await confirm(
                context,
                '刪除舊備份',
                '刪除',
                danger: true,
                body: List.filled(12, '這些備份用舊的金鑰加密，刪除後無法再還原。').join(),
              ),
            ),
            child: const Text('ask'),
          ),
        ),
      ),
    ),
  );

  testWidgets('a confirm with a long body scrolls it and keeps both choices '
      'in view, at 320 dp and 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final answers = <bool>[];
    await tester.pumpWidget(page(answers));
    await tester.tap(find.byKey(const ValueKey('ask')));
    await tester.pumpAndSettle();
    // No overflow: the words are in a scroll view, the choices are not.
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final confirmBox = tester.getRect(find.byKey(Keys.confirm));
    expect(confirmBox.bottom, lessThanOrEqualTo(screen.height));
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(answers, [true]);
  });

  /// A page whose button runs [ask] with its context.
  Widget asking(Future<void> Function(BuildContext context) ask) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            key: const ValueKey('ask'),
            onPressed: () => ask(context),
            child: const Text('ask'),
          ),
        ),
      ),
    ),
  );

  /// The material behind the choice of [key].
  Material fill(WidgetTester tester, Key key) => tester.widget<Material>(
    find.descendant(of: find.byKey(key), matching: find.byType(Material)),
  );

  testWidgets('askText is the confirm block: its title, a field, 取消 and '
      '完成; the line comes back trimmed, none when cancelled or blank '
      '(WP-E)', (tester) async {
    final answers = <String?>[];
    await tester.pumpWidget(
      asking((context) async => answers.add(await askText(context, '改名'))),
    );
    await tester.tap(find.byKey(const ValueKey('ask')));
    await tester.pumpAndSettle();
    expect(find.byType(DialogBlock), findsOneWidget);
    expect(find.text('改名'), findsOneWidget);
    expect(find.text(Words.done), findsOneWidget);
    expect(find.text('確定'), findsNothing);
    await tester.enterText(find.byKey(Keys.askedText), '  小明 ');
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ask')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(Keys.askedText), '小華');
    await tester.tap(find.byKey(Keys.confirmCancel));
    await tester.pumpAndSettle();

    // The keyboard's own done gives the line too.
    await tester.tap(find.byKey(const ValueKey('ask')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(Keys.askedText), '阿美');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ask')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(Keys.askedText), '   ');
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(answers, ['小明', null, '阿美', null]);
  });

  testWidgets('a choice that cannot be taken back is red, a plain yes the '
      'accent; the same frame for both (WP-E)', (tester) async {
    for (final (danger, colour) in [
      (true, AppColors.danger),
      (false, AppColors.accent),
    ]) {
      await tester.pumpWidget(
        asking(
          (context) => confirm(
            context,
            '停止備份？',
            '停止',
            danger: danger,
            body: '已經在雲端的備份會留著',
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('ask')));
      await tester.pumpAndSettle();
      expect(find.byType(DialogFrame), findsOneWidget);
      expect(find.text('已經在雲端的備份會留著'), findsOneWidget);
      // The light theme: a solid block of the colour.
      expect(fill(tester, Keys.confirm).color, colour, reason: '$danger');
      expect(fill(tester, Keys.confirmCancel).color, AppColors.surface);
      await tester.tap(find.byKey(Keys.confirmCancel));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('tell closes with 知道了; three choices stand one above '
      'another; a choice without an action is grey', (tester) async {
    await tester.pumpWidget(asking((context) => tell(context, '通知', '說明')));
    await tester.tap(find.byKey(const ValueKey('ask')));
    await tester.pumpAndSettle();
    expect(find.text(Words.gotIt), findsOneWidget);
    await tester.tap(find.byKey(Keys.confirm));
    await tester.pumpAndSettle();
    expect(find.byType(DialogBlock), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DialogBlock(
            title: '三個選擇',
            choices: [
              for (final word in ['一', '二'])
                DialogChoice(word, key: ValueKey(word), onTap: () {}),
              const DialogChoice('三', key: ValueKey('三'), onTap: null),
            ],
          ),
        ),
      ),
    );
    final one = tester.getRect(find.byKey(const ValueKey('一')));
    final two = tester.getRect(find.byKey(const ValueKey('二')));
    expect(two.top, greaterThan(one.bottom));
    expect(two.left, one.left);
    expect(fill(tester, const ValueKey('三')).color, AppColors.surface);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('三')),
              matching: find.byType(Text),
            ),
          )
          .style
          ?.color,
      AppColors.muted,
    );
  });
}
