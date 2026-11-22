import 'dart:convert';

import 'engine.dart';

/// Violations counted per rule and file: `{ruleId: {file: count}}`.
typedef Counts = Map<String, Map<String, int>>;

/// Counts [violations] per rule and file; every id in [ruleIds] appears,
/// even with no violations.
Counts countViolations(
  Iterable<Violation> violations,
  Iterable<String> ruleIds,
) {
  final counts = <String, Map<String, int>>{
    for (final id in ruleIds) id: <String, int>{},
  };
  for (final v in violations) {
    final files = counts.putIfAbsent(v.ruleId, () => <String, int>{});
    files[v.file] = (files[v.file] ?? 0) + 1;
  }
  return counts;
}

/// What a comparison of the current counts with the baseline found.
final class RatchetReport {
  const RatchetReport(this.growth, this.stale);

  /// Places with more violations than the baseline allows.
  final List<String> growth;

  /// Places with fewer violations than recorded: the baseline must shrink.
  final List<String> stale;

  bool get ok => growth.isEmpty && stale.isEmpty;
}

/// Compares [current] with [baseline] for [rules] (every rule of either
/// when null). Growth is a new violation; stale is a recorded one that is
/// gone, which the baseline must drop (`--update`).
RatchetReport compare(Counts current, Counts baseline, {Set<String>? rules}) {
  final ids = rules ?? {...current.keys, ...baseline.keys};
  final growth = <String>[];
  final stale = <String>[];
  for (final id in ids.toList()..sort()) {
    final now = current[id] ?? const <String, int>{};
    final recorded = baseline[id] ?? const <String, int>{};
    for (final file in {...now.keys, ...recorded.keys}.toList()..sort()) {
      final n = now[file] ?? 0;
      final r = recorded[file] ?? 0;
      if (n > r) {
        growth.add(
          r == 0
              ? '[$id] $file: $n new (not in the baseline)'
              : '[$id] $file: $n, the baseline allows $r',
        );
      } else if (n < r) {
        stale.add('[$id] $file: now $n, the baseline still says $r');
      }
    }
  }
  return RatchetReport(growth, stale);
}

/// The baseline after `--update`: [baseline] with the counts of [rules]
/// replaced by [current]. Returns the refused growth too; when it is not
/// empty and [allowGrowth] is false, the baseline is returned unchanged.
({Counts baseline, List<String> refused}) update(
  Counts current,
  Counts baseline, {
  required Set<String> rules,
  bool allowGrowth = false,
}) {
  final refused = compare(current, baseline, rules: rules).growth;
  if (refused.isNotEmpty && !allowGrowth) {
    return (baseline: baseline, refused: refused);
  }
  final next = <String, Map<String, int>>{
    for (final e in baseline.entries) e.key: {...e.value},
  };
  for (final id in rules) {
    next[id] = {...?current[id]};
  }
  return (baseline: next, refused: const []);
}

/// The JSON text of [counts]: sorted keys, two-space indent, no zero
/// counts, a final newline.
String encodeBaseline(Counts counts) {
  final sorted = <String, Object>{
    for (final id in counts.keys.toList()..sort())
      id: {
        for (final file in counts[id]!.keys.toList()..sort())
          if (counts[id]![file]! > 0) file: counts[id]![file]!,
      },
  };
  return '${const JsonEncoder.withIndent('  ').convert(sorted)}\n';
}

/// Reads a baseline written by [encodeBaseline].
Counts decodeBaseline(String text) {
  final json = jsonDecode(text) as Map<String, dynamic>;
  return {
    for (final e in json.entries)
      e.key: {
        for (final f in (e.value as Map<String, dynamic>).entries)
          f.key: f.value as int,
      },
  };
}
