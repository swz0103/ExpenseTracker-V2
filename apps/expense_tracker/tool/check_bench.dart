// Fails when an emulator-bench figure exceeds its limit.
//
//   dart run tool/check_bench.dart [results.json] [thresholds.json]
//
// Defaults: build/integration_response_data.json (what the bench writes) and
// test/perf/thresholds.json, run from apps/expense_tracker.
import 'dart:convert';
import 'dart:io';

/// One limit's verdict.
class BenchFinding {
  const BenchFinding(this.key, this.limit, this.value);

  final String key;
  final num limit;

  /// Null when the figure is missing or not a number.
  final num? value;

  bool get missing => value == null;
  bool get exceeded => value != null && value! > limit;
  bool get failed => missing || exceeded;

  @override
  String toString() => missing
      ? '$key: MISSING (limit $limit)'
      : '$key: $value ${exceeded ? '>' : '<='} $limit';
}

/// Reads [key] from [data]: an exact key first, else a dotted path into a
/// nested map (`save.average_frame_build_time_millis`).
num? readFigure(Map<String, dynamic> data, String key) {
  final exact = data[key];
  if (exact is num) return exact;
  final dot = key.indexOf('.');
  if (dot > 0) {
    final inner = data[key.substring(0, dot)];
    if (inner is Map<String, dynamic>) {
      return readFigure(inner, key.substring(dot + 1));
    }
  }
  return null;
}

/// Compares every limit with the bench's [data]; a limit with no figure fails.
List<BenchFinding> checkBench(
  Map<String, dynamic> data,
  Map<String, dynamic> limits,
) => [
  for (final entry in limits.entries)
    BenchFinding(entry.key, entry.value as num, readFigure(data, entry.key)),
];

void main(List<String> args) {
  final results = File(
    args.isNotEmpty ? args[0] : 'build/integration_response_data.json',
  );
  final thresholds = File(
    args.length > 1 ? args[1] : 'test/perf/thresholds.json',
  );
  if (!results.existsSync()) {
    stderr.writeln('No bench results at ${results.path}.');
    exit(1);
  }
  final findings = checkBench(
    jsonDecode(results.readAsStringSync()) as Map<String, dynamic>,
    jsonDecode(thresholds.readAsStringSync()) as Map<String, dynamic>,
  );
  for (final finding in findings) {
    stdout.writeln('${finding.failed ? 'FAIL' : 'ok  '} $finding');
  }
  final failed = findings.where((f) => f.failed).length;
  if (failed > 0) {
    stderr.writeln('$failed of ${findings.length} bench limits not met.');
    exit(1);
  }
  stdout.writeln('All ${findings.length} bench limits met.');
}
