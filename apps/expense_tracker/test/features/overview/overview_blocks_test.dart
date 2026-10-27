import 'package:expense_tracker/src/features/overview/model/overview_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the app order shows every block', () {
    final choices = blocksFrom(null);
    expect([for (final c in choices) c.block], OverviewBlock.values);
    expect(choices.every((c) => c.shown), isTrue);
  });

  test('a kept order reads back, hidden blocks included', () {
    final kept = ['flow', '!market', 'plan'];
    final choices = blocksFrom(kept);
    expect(choices.take(3).toList(), [
      (block: OverviewBlock.flow, shown: true),
      (block: OverviewBlock.market, shown: false),
      (block: OverviewBlock.plan, shown: true),
    ]);
    // Blocks not in the kept order come after, shown.
    expect(choices.skip(3).map((c) => c.block), [
      OverviewBlock.daily,
      OverviewBlock.assets,
    ]);
    expect(blocksToKeep(choices).take(3), kept);
  });

  test('unknown or repeated names are left out', () {
    final choices = blocksFrom(['weather', 'flow', '!flow']);
    expect(choices, hasLength(OverviewBlock.values.length));
    expect(choices.first, (block: OverviewBlock.flow, shown: true));
  });
}
