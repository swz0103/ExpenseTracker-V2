/// Rule C3: the characterization baseline under
/// apps/expense_tracker/test/baseline/ is only changed on purpose. A pull
/// request that modifies or deletes an existing baseline file must say why in
/// a commit message with a `Baseline-Change: <reason>` line; adding new
/// baseline files needs nothing.
library;

const baselineDirectory = 'apps/expense_tracker/test/baseline/';

/// The baseline files that [nameStatus] (the output of
/// `git diff --no-renames --name-status`) modifies, deletes or retypes.
/// Added files are fine. Paths may be quoted by git when they hold unusual
/// characters; the quotes are stripped.
List<String> changedBaselineFiles(String nameStatus) {
  final changed = <String>[];
  for (final line in nameStatus.split('\n')) {
    final parts = line.trimRight().split('\t');
    if (parts.length < 2) continue;
    final status = parts.first;
    if (status.isEmpty || status.startsWith('A')) continue;
    // Without --no-renames or copy detection, every path involved counts:
    // a renamed-away baseline file is a deleted one.
    final paths = status.startsWith('C') ? [parts[1]] : parts.sublist(1);
    for (final path in paths) {
      final clean = path.length >= 2 && path.startsWith('"')
          ? path.substring(1, path.length - 1)
          : path;
      if (clean.startsWith(baselineDirectory)) changed.add(clean);
    }
  }
  return changed;
}

final _reason = RegExp(r'^Baseline-Change:[ \t]*\S', multiLine: true);

/// Whether any commit message in [log] (`git log --format=%B`) carries a
/// `Baseline-Change: <reason>` line with a non-empty reason.
bool hasBaselineReason(String log) => _reason.hasMatch(log);
