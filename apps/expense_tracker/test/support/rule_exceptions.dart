/// An exception to a rule, marked where it is made: a comment
/// `// Exception to <rule>: <why>` on the line itself or in the comments
/// just above it, or, for the whole file, among the comments at its top.
/// The rule tests read these marks instead of naming files, so a file
/// keeps its exception when it moves, and the reason is read beside the
/// code it excuses.
library;

String _mark(String rule) => 'Exception to $rule:';

/// Whether line [index] of [lines] is excused from [rule]: marked on the
/// line, or in the comment lines right above it.
bool excusedAt(List<String> lines, int index, String rule) {
  final mark = _mark(rule);
  if (lines[index].contains(mark)) return true;
  for (var i = index - 1; i >= 0; i--) {
    final line = lines[i].trimLeft();
    if (!line.startsWith('//')) return false;
    if (line.contains(mark)) return true;
  }
  return false;
}

/// Whether the whole file of [lines] is excused from [rule]: marked in the
/// comments before its first line of code.
bool excusedFile(List<String> lines, String rule) {
  final mark = _mark(rule);
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty || trimmed.startsWith('//')) {
      if (trimmed.contains(mark)) return true;
      continue;
    }
    return false;
  }
  return false;
}
