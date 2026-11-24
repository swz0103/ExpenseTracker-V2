import '../model/entry.dart';

/// The category a category of a name sits under, or null for one at the
/// top (or a name no category has).
typedef ParentOf = String? Function(String name);

/// The categories from [name] up to the top: [name] itself, the one it
/// sits under, and so on. A loop of parents, which no form lets through,
/// ends where it would come round again.
List<String> lineOf(String name, ParentOf parentOf) {
  final line = [name];
  for (var at = parentOf(name); at != null; at = parentOf(at)) {
    if (line.contains(at)) break;
    line.add(at);
  }
  return line;
}

/// Whether the category [name] is [under] or one of its subcategories,
/// at any depth: the one meaning of "under category X" that budgets,
/// reports and the entry filter all ask (D54).
bool isUnder(String name, String under, ParentOf parentOf) =>
    lineOf(name, parentOf).contains(under);

/// The category at the top of [name]'s line: what [name]'s spending is
/// counted under when categories are counted with their subcategories.
String topOf(String name, ParentOf parentOf) => lineOf(name, parentOf).last;

/// What of [e]'s spending is under [category] ([isUnder]): its parts in
/// [category] or one of its subcategories; negative for a refund.
int spendingUnder(Entry e, String category, ParentOf parentOf) {
  var total = 0;
  for (final (name, value) in e.spendingParts) {
    if (isUnder(name, category, parentOf)) total += value;
  }
  return total;
}

/// Whether [e], or a part of its split, is under [category] ([isUnder]).
bool entryIsUnder(Entry e, String category, ParentOf parentOf) =>
    isUnder(e.category, category, parentOf) ||
    e.parts.any((p) => isUnder(p.$1, category, parentOf));

/// [byName], amounts by category, counted with their subcategories under
/// the category at the top of each ([topOf]), in the order the tops are
/// first met.
Map<String, int> byTopCategory(Map<String, int> byName, ParentOf parentOf) {
  final totals = <String, int>{};
  for (final MapEntry(:key, :value) in byName.entries) {
    final top = topOf(key, parentOf);
    totals[top] = (totals[top] ?? 0) + value;
  }
  return totals;
}
