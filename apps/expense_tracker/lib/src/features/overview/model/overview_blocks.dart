/// The blocks of 總覽 below its main figures, which the person may put in
/// another order or hide.
enum OverviewBlock {
  plan('預算與即將扣款'),
  daily('每日紀錄'),
  market('投資行情'),
  assets('財務分布'),
  flow('收支對照');

  const OverviewBlock(this.label);

  final String label;
}

/// One block as the person set it: where it is, and whether it shows.
typedef BlockChoice = ({OverviewBlock block, bool shown});

/// The blocks in the order kept as [kept] (names, a hidden one written
/// `!name`), every block once: those the app adds later come last, shown;
/// names it no longer knows are left out. Null gives the app's order.
List<BlockChoice> blocksFrom(List<String>? kept) {
  final choices = <BlockChoice>[];
  final seen = <OverviewBlock>{};
  for (final word in kept ?? const <String>[]) {
    final hidden = word.startsWith('!');
    final name = hidden ? word.substring(1) : word;
    for (final block in OverviewBlock.values) {
      if (block.name == name && seen.add(block)) {
        choices.add((block: block, shown: !hidden));
      }
    }
  }
  for (final block in OverviewBlock.values) {
    if (seen.add(block)) choices.add((block: block, shown: true));
  }
  return choices;
}

/// [choices] as kept in the preferences.
List<String> blocksToKeep(List<BlockChoice> choices) => [
  for (final (:block, :shown) in choices) shown ? block.name : '!${block.name}',
];
